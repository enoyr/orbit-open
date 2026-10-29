import AppKit
import PDFKit
import SwiftUI

struct OrbitLocalFile {
    let name: String
    let content: String
    let wasTruncated: Bool

    static func load(_ url: URL) throws -> OrbitLocalFile {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 5_000_000 else {
            throw OrbitFileError.tooLarge
        }
        let raw: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let text = PDFDocument(url: url)?.string else { throw OrbitFileError.unreadable }
            raw = text
        } else {
            let extensions: Set<String> = ["txt", "md", "csv", "json", "log", "swift", "py",
                                           "js", "ts", "html", "css", "xml", "yaml", "yml", "sql", "sh"]
            guard extensions.contains(url.pathExtension.lowercased()) else {
                throw OrbitFileError.unsupported
            }
            raw = try String(contentsOf: url, encoding: .utf8)
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrbitFileError.unreadable
        }
        return OrbitLocalFile(name: url.lastPathComponent, content: String(raw.prefix(100_000)),
                              wasTruncated: raw.count > 100_000)
    }
}

private enum OrbitFileError: LocalizedError {
    case tooLarge, unreadable, unsupported

    var errorDescription: String? {
        switch self {
        case .tooLarge: "Il file supera 5 MB o non è un file normale."
        case .unreadable: "Non riesco a leggere il testo di questo file."
        case .unsupported: "Per ora posso leggere PDF e file di testo o codice."
        }
    }
}

struct OrbitFilePanel: View {
    let file: OrbitLocalFile
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(OrbitPalette.blue)
                Text(file.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi anteprima")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            Divider()
            ScrollView {
                Text(file.content)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
            if file.wasTruncated {
                Text("Anteprima limitata ai primi 100.000 caratteri")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(minWidth: 300, idealWidth: 400)
        .background(.regularMaterial)
    }
}
