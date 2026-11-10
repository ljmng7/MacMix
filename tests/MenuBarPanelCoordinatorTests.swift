import AppKit

// Unrelated collaborators are replaced here so the real coordinator can be
// exercised against native windows without starting audio capture or routing.
struct AudioAppState {}
enum SystemVolumePanelMode { case fullPanel, systemVolume, outputPanel }
enum MenuBarIconMetrics { static let statusItemLength: CGFloat = 40 }
@MainActor final class MenuBarIconAnimator {
    func attach(to button: NSStatusBarButton) {}
}
@MainActor final class DiagnosticLog {
    static let shared = DiagnosticLog()
    func record(_ category: String, _ event: String, fields: [String: String] = [:]) {}
}
extension Notification.Name {
    static let airPlayRoutePickerPresentationChanged = Notification.Name("PanelTest.RoutePicker")
}

@main
struct MenuBarPanelCoordinatorTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let item = NSStatusBar.system.statusItem(withLength: 40)
        item.button?.title = "Test"
        let coordinator = MenuBarPanelCoordinator()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 150, width: 320, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        func settle(_ duration: TimeInterval = 0.08) {
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
        }
        settle()
        coordinator.attachStatusItem(item)
        panel.orderFront(nil)
        coordinator.attachPanelWindow(panel)
        guard let anchor = item.button?.window, let screen = anchor.screen else {
            preconditionFailure("A GUI session and status-item window are required")
        }
        let available = MenuBarPanelPlacement.maximumHeight(anchor: anchor.frame, visibleFrame: screen.visibleFrame)
        let expanded = min(900, available)
        let collapsed = min(300, available)
        func expect(_ height: CGFloat, _ message: String) {
            settle()
            let contentHeight = panel.contentRect(forFrameRect: panel.frame).height
            let expectedTop = min(anchor.frame.minY, screen.visibleFrame.maxY) - MenuBarPanelPlacement.menuBarGap
            precondition(abs(contentHeight - height) < 1, "\(message): incorrect content height")
            precondition(abs(panel.frame.maxY - expectedTop) < 1.5, "\(message): panel top drifted")
            precondition(panel.frame.minY >= screen.visibleFrame.minY - 1, "\(message): panel overlaps Dock")
            print("PASS: \(message)")
        }
        coordinator.notePanelContentHeight(expanded)
        expect(expanded, "initial visible window is positioned below its status item")
        coordinator.notePanelContentHeight(collapsed)
        expect(collapsed, "collapsing content resizes and top-anchors the same retained window")
        coordinator.notePanelContentHeight(expanded)
        expect(expanded, "expanding content restores the full height without shifting its top")
        coordinator.notePanelContentHeight(available + 500)
        expect(available, "oversized content is limited to the visible screen")
        panel.orderOut(nil)
        coordinator.presentTemporary(mode: .systemVolume)
        coordinator.notePanelContentHeight(84)
        panel.orderFront(nil)
        expect(84, "temporary volume panel does not retain full-panel height")
        coordinator.dismissTemporaryPanel()
        panel.orderOut(nil)
        settle(0.6)
        coordinator.notePanelContentHeight(expanded)
        coordinator.isPresented = true
        panel.orderFront(nil)
        expect(expanded, "full panel restores its height and anchor after temporary mode")
        panel.close()
        NSStatusBar.system.removeStatusItem(item)
        print("All 6 native menu-panel coordinator checks passed.")
    }
}
