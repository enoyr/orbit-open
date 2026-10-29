import AppKit
import SwiftUI

/// Keeps macOS scrolling and accessibility while using its small overlay scroller.
struct OrbitOverlayScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(from: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(from: view) }
    }

    private func configure(from view: NSView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.controlSize = .small
                return
            }
            ancestor = current.superview
        }
    }
}
