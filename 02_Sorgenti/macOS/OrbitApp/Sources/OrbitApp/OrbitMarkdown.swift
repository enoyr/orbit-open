import AppKit
import Charts
import SwiftUI

private enum MessageBlock: Identifiable {
    case prose(Int, String)
    case code(Int, String, String)
    case table(Int, [[String]])
    case chart(Int, String, [ChartPoint])
    case heading(Int, Int, String)
    case list(Int, [(String, String)])
    case quote(Int, String)
    case rule(Int)

    var id: Int {
        switch self {
        case .prose(let id, _), .code(let id, _, _), .table(let id, _),
             .chart(let id, _, _), .heading(let id, _, _), .list(let id, _),
             .quote(let id, _), .rule(let id): id
        }
    }
}

private struct ChartPoint: Decodable, Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

private struct ChartDocument: Decodable {
    let title: String?
    let data: [ChartPoint]
}

private enum MessageParser {
    static func parse(_ source: String) -> [MessageBlock] {
        let lines = source.components(separatedBy: "\n")
        var result: [MessageBlock] = []
        var prose: [String] = []
        var index = 0
        func flush() {
            guard !prose.isEmpty else { return }
            result.append(.prose(result.count, prose.joined(separator: "\n")))
            prose.removeAll()
        }
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                flush()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                let body = code.joined(separator: "\n")
                if language == "chart", let data = body.data(using: .utf8),
                   let chart = try? JSONDecoder().decode(ChartDocument.self, from: data),
                   !chart.data.isEmpty {
                    result.append(.chart(result.count, chart.title ?? "Grafico", chart.data))
                } else {
                    result.append(.code(result.count, language, body))
                }
            } else if line == "---" || line == "***" {
                flush()
                result.append(.rule(result.count))
            } else if let prefix = headingLevel(line) {
                flush()
                result.append(.heading(result.count, prefix,
                                       String(line.dropFirst(prefix + 1))))
            } else if line.hasPrefix("> ") {
                flush()
                var quotes: [String] = []
                while index < lines.count && lines[index].hasPrefix("> ") {
                    quotes.append(String(lines[index].dropFirst(2)))
                    index += 1
                }
                result.append(.quote(result.count, quotes.joined(separator: "\n")))
                continue
            } else if let item = listItem(line) {
                flush()
                var items = [item]
                index += 1
                while index < lines.count, let next = listItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                result.append(.list(result.count, items))
                continue
            } else if line.contains("|") && index + 1 < lines.count &&
                        lines[index + 1].replacingOccurrences(of: "|", with: "")
                            .trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) &&
                        lines[index + 1].contains("-") {
                flush()
                var rows: [[String]] = [cells(line)]
                index += 2
                while index < lines.count && lines[index].contains("|") && !lines[index].isEmpty {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                result.append(.table(result.count, rows))
                continue
            } else {
                prose.append(line)
            }
            index += 1
        }
        flush()
        return result
    }

    private static func cells(_ line: String) -> [String] {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func listItem(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return ("•", String(trimmed.dropFirst(2)))
        }
        let number = trimmed.prefix(while: { $0.isNumber })
        if !number.isEmpty, trimmed.dropFirst(number.count).hasPrefix(". ") {
            return ("\(number).", String(trimmed.dropFirst(number.count + 2)))
        }
        return nil
    }

    private static func headingLevel(_ line: String) -> Int? {
        let level = line.prefix(while: { $0 == "#" }).count
        return (1...6).contains(level) && line.dropFirst(level).hasPrefix(" ") ? level : nil
    }
}

struct OrbitCopyButton: View {
    let text: String
    var label = "Copia"
    var iconOnly = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                } else {
                    Label(copied ? "Copiato" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(copied ? "Copiato" : label)
    }
}

struct OrbitMarkdownMessage: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(MessageParser.parse(content)) { block in
                switch block {
                case .prose(_, let text):
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                case .code(_, let language, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(language.isEmpty ? "Codice" : language)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            OrbitCopyButton(text: code, label: "Copia codice")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        Divider()
                        ScrollView(.horizontal) {
                            Text(code)
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                case .table(_, let rows):
                    ScrollView(.horizontal) {
                        Grid(horizontalSpacing: 18, verticalSpacing: 10) {
                            ForEach(rows.indices, id: \.self) { rowIndex in
                                GridRow {
                                    ForEach(rows[rowIndex].indices, id: \.self) { cellIndex in
                                        Text(rows[rowIndex][cellIndex])
                                            .font(.system(size: 13, weight: rowIndex == 0 ? .semibold : .regular))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                if rowIndex == 0 { Divider() }
                            }
                        }
                        .padding(13)
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                case .chart(_, let title, let points):
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.headline)
                        Chart(points) { point in
                            BarMark(x: .value("Voce", point.label), y: .value("Valore", point.value))
                                .foregroundStyle(OrbitPalette.actionBlue)
                        }
                        .frame(height: 220)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                case .heading(_, let level, let text):
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .font(.system(size: level == 1 ? 23 : level == 2 ? 19 : 16,
                                      weight: .semibold))
                        .textSelection(.enabled)
                        .padding(.top, 5)
                case .list(_, let items):
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(items.indices, id: \.self) { index in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(items[index].0).frame(width: 20, alignment: .trailing)
                                Text((try? AttributedString(markdown: items[index].1))
                                     ?? AttributedString(items[index].1))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .font(.system(size: 15))
                case .quote(_, let text):
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 14)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OrbitPalette.actionBlue.opacity(0.55))
                                .frame(width: 3)
                        }
                case .rule:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
