import AppKit
import SwiftUI

enum OrbitPalette {
    static let actionBlue = Color(nsColor: .systemBlue)
    static let blue = Color(red: 0.216, green: 0.345, blue: 1.0)
    static let cyan = Color(red: 0.22, green: 0.67, blue: 0.96)
    static let teal = Color(red: 0.0, green: 0.776, blue: 0.69)
    static let yellow = Color(red: 243.0 / 255, green: 229.0 / 255, blue: 0)
    static let violet = Color(red: 191.0 / 255, green: 54.0 / 255, blue: 195.0 / 255)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.12)
    static let accent = LinearGradient(
        colors: [blue, cyan, teal], startPoint: .leading, endPoint: .trailing
    )
}

struct OrbitGlassControl: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule).tint(.clear)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

enum OrbitLayout {
    static let sidebarCollapseWidth: CGFloat = 900
    static let homeActionStackWidth: CGFloat = 760
}

struct OrbitAtmosphere: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Ellipse()
                    .fill(OrbitPalette.blue.opacity(0.26))
                    .frame(width: geometry.size.width * 0.72, height: geometry.size.height * 0.62)
                    .blur(radius: 100)
                    .offset(x: -geometry.size.width * 0.28, y: -geometry.size.height * 0.30)
                Ellipse()
                    .fill(OrbitPalette.teal.opacity(0.23))
                    .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.68)
                    .blur(radius: 105)
                    .offset(x: geometry.size.width * 0.38, y: geometry.size.height * 0.23)
                Ellipse()
                    .fill(OrbitPalette.orange.opacity(0.14))
                    .frame(width: geometry.size.width * 0.40, height: geometry.size.height * 0.42)
                    .blur(radius: 85)
                    .offset(x: geometry.size.width * 0.1, y: -geometry.size.height * 0.2)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct OrbitWordmark: View {
    var size: CGFloat = 48

    var body: some View {
        OrbitGradientTitle(text: "Orbit", size: size)
    }
}

struct OrbitGradientTitle: View {
    let text: String
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(String(text.prefix(1))).foregroundStyle(OrbitPalette.accent)
            Text(String(text.dropFirst())).foregroundStyle(.primary)
        }
        .font(.system(size: size, weight: .ultraLight))
        .tracking(size * 0.055)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct OrbitWave: View {
    var height: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.72
            let colors = Gradient(colors: [
                OrbitPalette.blue, OrbitPalette.teal, OrbitPalette.yellow,
                OrbitPalette.violet, OrbitPalette.orange
            ])
            for index in 0..<40 {
                var path = Path()
                let depth = Double(index) - 20
                let weight = 1 - abs(depth) / 20
                let opacity = 0.05 + weight * 0.20
                let amplitude = (30 + 80 * pow(weight, 2.2)) * Double(size.height / 260)
                for step in 0...240 {
                    let x = size.width * CGFloat(step) / 240
                    let d = Double(step) / 120 - 1
                    let oscillation = sin(d * .pi * 2 + phase + depth * 0.15) * 0.6
                        + sin(d * .pi * 6 + phase * 0.8 - depth * 0.25) * 0.4
                    let envelope = pow(1 - abs(d), 3)
                    let y = size.height * 0.5 + CGFloat(oscillation * amplitude * envelope * weight)
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.opacity = opacity
                context.stroke(
                    path,
                    with: .linearGradient(
                        colors,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    lineWidth: 0.8
                )
            }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct OrbitSidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(selected ? 0.07 : 0.001),
                            in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct OrbitConversationSidebarRow: View {
    let title: String
    let selected: Bool
    let alwaysShowActions: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    private var showsActions: Bool { isHovered || alwaysShowActions }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .frame(width: 18)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            Menu {
                Button("Rinomina", systemImage: "pencil", action: onRename)
                Button("Elimina chat", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 26)
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
            .accessibilityLabel("Modifica \(title)")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(selected ? 0.07 : isHovered ? 0.04 : 0.001),
                    in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Rinomina", systemImage: "pencil", action: onRename)
            Button("Elimina chat", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

struct OrbitActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var ready = true

    var body: some View {
        if #available(macOS 26, *) {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .disabled(!ready)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .disabled(!ready)
        }
    }

    private var label: some View {
        Label(title, systemImage: symbol)
    }
}

struct OrbitTextActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var ready = true
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                Text(title).underline()
            }
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(OrbitPalette.actionBlue)
                .opacity(ready ? (isHovered ? 0.72 : 1) : 0.45)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .onHover { hovering in
            guard hovering != isHovered else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

struct OrbitSettingsField<Content: View>: View {
    let title: String
    var help: String? = nil
    var surface = true
    let content: Content

    init(_ title: String, help: String? = nil, surface: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if surface {
                content
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.11), lineWidth: 1)
                    }
            } else {
                content
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OrbitSaveConfirmation: View {
    let title: String
    let detail: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(OrbitPalette.actionBlue, in: Circle())
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                OrbitWave(height: 54)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                HStack {
                    Spacer()
                    OrbitTextActionButton(title: "Continua", symbol: "arrow.right", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(25)
            .frame(width: 390)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 28, y: 14)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}
