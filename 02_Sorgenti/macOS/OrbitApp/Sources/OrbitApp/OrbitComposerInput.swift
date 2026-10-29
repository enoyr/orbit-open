import AppKit
import SwiftUI

fileprivate final class OrbitComposerTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.shift) {
            insertNewlineIgnoringFieldEditor(self)
            return
        }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }
}

struct OrbitComposerInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusID: UUID
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false

        let input = OrbitComposerTextView()
        input.font = .systemFont(ofSize: 17)
        input.textColor = .labelColor
        input.insertionPointColor = .labelColor
        input.drawsBackground = false
        input.isRichText = false
        input.importsGraphics = false
        input.allowsUndo = true
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainerInset = .zero
        input.textContainer?.lineFragmentPadding = 0
        input.textContainer?.widthTracksTextView = true
        input.string = text
        input.onSend = onSend
        input.delegate = context.coordinator
        scrollView.documentView = input
        context.coordinator.input = input
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let input = context.coordinator.input else { return }
        context.coordinator.parent = self
        input.onSend = onSend
        if input.string != text { input.string = text }
        context.coordinator.updateHeight()
        if context.coordinator.focusedID != focusID {
            DispatchQueue.main.async {
                guard let window = scrollView.window else { return }
                window.makeFirstResponder(input)
                context.coordinator.focusedID = focusID
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OrbitComposerInput
        fileprivate weak var input: OrbitComposerTextView?
        var focusedID: UUID?

        init(_ parent: OrbitComposerInput) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let input else { return }
            parent.text = input.string
            updateHeight()
        }

        func updateHeight() {
            guard let input, let container = input.textContainer,
                  let layout = input.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height
            let desired = min(max(ceil(used) + 8, 52), 204)
            if abs(parent.height - desired) > 1 {
                DispatchQueue.main.async { self.parent.height = desired }
            }
        }
    }
}
