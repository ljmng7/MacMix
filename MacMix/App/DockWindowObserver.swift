import AppKit
import SwiftUI

struct DockWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAnchor() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAnchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { ApplicationDockVisibility.shared.track(window) }
        }
    }
}
