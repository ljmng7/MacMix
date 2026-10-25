import AppKit
import Observation

@MainActor
@Observable
final class MenuBarPanelCoordinator {
    private static let inactivityDuration = Duration.seconds(1)
    private static let presentationDelay = Duration.milliseconds(32)
    private static let dismissalCleanupDelay = Duration.milliseconds(500)

    var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            DiagnosticLog.shared.record("interface", "menu_panel_visibility", fields: ["visible": String(isPresented)])
            if !isPresented {
                scheduleDismissalCleanup()
            } else {
                presentationTask?.cancel()
                presentationTask = nil
                dismissalCleanupTask?.cancel()
                dismissalCleanupTask = nil
                if !isTemporary {
                    mode = .fullPanel
                }
                // SwiftUI places the window during this presentation; check it
                // against the status item once that placement has landed.
                Task { @MainActor [weak self] in self?.alignPanelToStatusItem(trigger: "presented") }
            }
        }
    }

    private(set) var mode: SystemVolumePanelMode = .fullPanel
    private(set) var isTemporary = false
    private(set) var sceneFeedback: ScenePanelFeedback?
    private(set) var volumeApp: AudioAppState?
    @ObservationIgnored weak var mainWindow: NSWindow?

    func presentAppVolume(_ app: AudioAppState) {
        presentTemporary(mode: .systemVolume)
        guard isTemporary else { return }
        volumeApp = app
    }

    func presentSceneFeedback(_ feedback: ScenePanelFeedback) {
        presentTemporary(mode: .systemVolume)
        guard isTemporary else { return }
        sceneFeedback = feedback
    }

    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var presentationTask: Task<Void, Never>?
    @ObservationIgnored private var dismissalCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var isPointerInside = false
    @ObservationIgnored private weak var panelWindow: NSWindow?
    @ObservationIgnored private weak var statusItemWindow: NSWindow?
    @ObservationIgnored private var panelWindowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusItemObservers: [NSObjectProtocol] = []

    func presentTemporary(mode: SystemVolumePanelMode) {
        sceneFeedback = nil
        volumeApp = nil
        if let panelWindow {
            if panelWindow.isVisible {
                if !isTemporary {
                    return
                }

                if isPresented {
                    self.mode = mode
                    noteTemporaryActivity()
                    return
                }
            } else if isPresented {
                // MenuBarExtraAccess can briefly leave its binding true after
                // the underlying window has already disappeared. Force a real
                // edge so the next true value performs a presentation.
                isPresented = false
            }
        } else if isPresented {
            // Before the first window introspection, the binding is the only
            // reliable indication that the regular panel is already open.
            if isTemporary {
                self.mode = mode
                noteTemporaryActivity()
            }
            return
        }

        self.mode = mode
        isTemporary = true
        guard presentationTask == nil else { return }

        presentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.presentationDelay)
            } catch {
                return
            }

            guard let self else { return }
            presentationTask = nil

            guard isTemporary else { return }
            if isPresented, panelWindow?.isVisible != true {
                isPresented = false
                await Task.yield()
            }

            guard isTemporary, !isPresented else { return }
            isPresented = true
        }
    }

    func attachPanelWindow(_ window: NSWindow) {
        guard panelWindow !== window else { return }
        panelWindow = window
        panelWindowObservers = observeGeometry(of: window, trigger: "panel_geometry")
        if statusItemWindow == nil,
           let statusBarWindow = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") }) {
            // The status item introspection runs once at launch and can precede the runtime.
            attachStatusItemWindow(statusBarWindow)
        }
        alignPanelToStatusItem(trigger: "panel_attached")
    }

    func attachStatusItem(_ statusItem: NSStatusItem) {
        keepStatusItemWidthStable(statusItem)
        guard let window = statusItem.button?.window else { return }
        attachStatusItemWindow(window)
    }

    /// The muted symbol is narrower than the audible one. With a variable
    /// length the item would resize, and shift an open panel, on every mute
    /// change; a fixed length keeps it steady while the button centres the
    /// symbol. Wider scene symbols still get room.
    private func keepStatusItemWidthStable(_ statusItem: NSStatusItem) {
        let symbolWidth = statusItem.button?.image?.size.width ?? 0
        statusItem.length = max(MenuBarIconMetrics.statusItemLength, ceil(symbolWidth))
    }

    private func attachStatusItemWindow(_ window: NSWindow) {
        guard statusItemWindow !== window else { return }
        statusItemWindow = window
        statusItemObservers = observeGeometry(of: window, trigger: "status_item_moved")
        DiagnosticLog.shared.record("interface", "menu_panel_anchor_attached", fields: [
            "anchor_x": String(format: "%.1f", window.frame.minX),
            "anchor_width": String(format: "%.1f", window.frame.width)
        ])
    }

    private func observeGeometry(of window: NSWindow, trigger: String) -> [NSObjectProtocol] {
        [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.alignPanelToStatusItem(trigger: trigger) }
            }
        }
    }

    /// MenuBarExtra aligns the panel with the status item only when it shows
    /// or resizes the window. If the status item moved in between (its own icon
    /// or a neighbour changed width, which is common right after launch), the
    /// panel stays misaligned until a large content change resizes it.
    private func alignPanelToStatusItem(trigger: String) {
        guard let panel = panelWindow, panel.isVisible,
              let anchor = statusItemWindow?.frame, anchor.width > 0,
              let screen = panel.screen ?? statusItemWindow?.screen else { return }

        // MenuBarExtra aligns the panel's leading edge with the status item's.
        let target = anchor.minX.rounded()
        if trigger == "presented" {
            DiagnosticLog.shared.record("interface", "menu_panel_geometry", fields: [
                "panel_x": String(Int(panel.frame.minX)),
                "panel_width": String(Int(panel.frame.width)),
                "anchor_x": String(format: "%.1f", anchor.minX),
                "anchor_width": String(format: "%.1f", anchor.width)
            ])
        }
        // Leave edge-clamped placements to SwiftUI, and ignore 1 pt rounding
        // differences so the two never correct each other back and forth.
        guard target >= screen.frame.minX, target + panel.frame.width <= screen.frame.maxX,
              abs(panel.frame.minX - target) >= 1.5 else { return }

        DiagnosticLog.shared.record("interface", "menu_panel_realigned", fields: [
            "trigger": trigger,
            "from_x": String(Int(panel.frame.minX)),
            "to_x": String(Int(target)),
            "anchor_x": String(format: "%.1f", anchor.minX),
            "panel_width": String(Int(panel.frame.width))
        ])
        panel.setFrameOrigin(NSPoint(x: target, y: panel.frame.minY))
    }

    func dismissTemporaryPanel() {
        guard isTemporary else { return }

        presentationTask?.cancel()
        presentationTask = nil

        if isPresented {
            isPresented = false
        } else {
            isTemporary = false
            mode = .fullPanel
        }
    }

    func panelDidAppear() {
        if isTemporary {
            noteTemporaryActivity()
        }
    }

    func noteTemporaryActivity() {
        guard isPresented, isTemporary else { return }
        hideTask?.cancel()
        guard !isPointerInside else {
            hideTask = nil
            return
        }

        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.inactivityDuration)
            } catch {
                return
            }
            self?.dismissTemporaryPanel()
        }
    }

    func setPointerInside(_ isInside: Bool) {
        guard isTemporary else { return }
        isPointerInside = isInside
        if isInside {
            hideTask?.cancel()
            hideTask = nil
        } else {
            noteTemporaryActivity()
        }
    }

    private func scheduleDismissalCleanup() {
        hideTask?.cancel()
        hideTask = nil
        isPointerInside = false

        dismissalCleanupTask?.cancel()
        dismissalCleanupTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.dismissalCleanupDelay)
            } catch {
                return
            }

            guard let self, !isPresented else { return }
            isTemporary = false
            mode = .fullPanel
            dismissalCleanupTask = nil
        }
    }
}

struct ScenePanelFeedback {
    let name: String
    let symbol: String
    let color: String
    let isEnabled: Bool
}
