import AppKit

@main
struct DockVisibilityTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        var menuBarVisible = true
        let visibility = ApplicationDockVisibility(showsMenuBarItem: { menuBarVisible })

        func expect(_ policy: NSApplication.ActivationPolicy, _ message: String) {
            precondition(app.activationPolicy() == policy, message)
            print("PASS: \(message)")
        }
        func window() -> NSWindow {
            let result = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            result.isReleasedWhenClosed = false
            visibility.track(result)
            return result
        }
        func show(_ window: NSWindow) {
            // Match both production open paths, which promote and activate
            // the app before displaying an existing SwiftUI window.
            app.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            visibility.refresh()
        }

        visibility.refresh()
        expect(.accessory, "menu-bar launch has no Dock icon")
        let main = window()
        show(main)
        expect(.regular, "opening Settings shows the Dock icon")
        main.close()
        expect(.accessory, "closing Settings hides the Dock icon")
        show(main)
        expect(.regular, "reopening a retained Settings window restores the Dock icon")
        let feedback = window()
        show(feedback)
        main.close()
        expect(.regular, "Feedback keeps the Dock icon after Settings closes")
        feedback.close()
        expect(.accessory, "closing the last window hides the Dock icon")
        show(main)
        show(feedback)
        feedback.close()
        expect(.regular, "Settings keeps the Dock icon after Feedback closes")
        main.close()
        expect(.accessory, "closing Settings last hides the Dock icon")
        menuBarVisible = false
        visibility.refresh()
        expect(.regular, "hiding the menu-bar item preserves access from the Dock")
        menuBarVisible = true
        visibility.refresh()
        expect(.accessory, "restoring the menu-bar item hides the idle Dock icon")
        let hiddenWindow = window()
        // This window is intentionally not shown; a hidden tracked view does
        // not make the application a regular app.
        visibility.refresh()
        expect(.accessory, "retained hidden windows do not keep a Dock icon")
        hiddenWindow.close()
        print("All Dock window lifecycle checks passed.")
    }
}
