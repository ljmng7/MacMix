import AppKit

// A single nonmodal alert window belongs to the audio model, not a SwiftUI page.
@MainActor
final class SceneActivationNoticeController: NSObject, NSWindowDelegate {
    private var alert: NSAlert?

    func present(message: String) {
        dismiss()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Scene Presets")
        alert.informativeText = message
        let button = alert.addButton(withTitle: String(localized: "OK"))
        button.target = self
        button.action = #selector(closeNotice)
        button.keyEquivalent = "\r"
        alert.layout()
        alert.window.delegate = self
        alert.window.isReleasedWhenClosed = false
        alert.window.level = .floating
        self.alert = alert
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let previous = alert
        alert = nil
        previous?.window.close()
    }

    @objc private func closeNotice() { dismiss() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === alert?.window else { return }
        alert = nil
    }
}
