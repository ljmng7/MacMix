import AppKit
import SwiftUI

/// SwiftUI can restore registered windows before launch authorization. Keep their empty placeholders hidden.
struct PendingLaunchWindowPlaceholder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiddenPendingLaunchWindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? HiddenPendingLaunchWindowView)?.restoreWindow()
    }
}

private final class HiddenPendingLaunchWindowView: NSView {
    private weak var hiddenWindow: NSWindow?

    func restoreWindow() { hiddenWindow?.alphaValue = 1 }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hiddenWindow = window
        window?.alphaValue = 0
        window?.orderOut(nil)
    }
}
