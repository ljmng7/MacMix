import AppKit
import Observation

@MainActor
@Observable
final class MenuBarPanelCoordinator {
    private static let inactivityDuration = Duration.seconds(1)
    private static let touchInactivityDuration = Duration.seconds(3)
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
    private(set) var maximumPanelHeight = MenuBarPanelPlacement.maximumHeight(
        anchor: nil, visibleFrame: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
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
    @ObservationIgnored private var isPressedInside = false
    @ObservationIgnored private var isRoutePickerOpen = false
    @ObservationIgnored private var routePickerObserver: NSObjectProtocol?
    @ObservationIgnored private var temporaryInactivityDuration = inactivityDuration
    @ObservationIgnored private var panelPressMonitor: Any?
    @ObservationIgnored private weak var panelWindow: NSWindow?
    @ObservationIgnored let iconAnimator = MenuBarIconAnimator()
    @ObservationIgnored private weak var statusItemWindow: NSWindow?
    @ObservationIgnored private var panelWindowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusItemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenParametersObserver: NSObjectProtocol?
    @ObservationIgnored private var isAligningPanel = false
    @ObservationIgnored private var alignmentScheduled = false
    @ObservationIgnored private var panelContentHeight: CGFloat = 0

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
        if panelWindow !== window {
            for observer in panelWindowObservers { NotificationCenter.default.removeObserver(observer) }
            panelWindow = window
            panelWindowObservers = observeGeometry(of: window, trigger: "panel_geometry")
            installPanelPressMonitor()
        }
        if screenParametersObserver == nil {
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.alignPanelToStatusItem(trigger: "screens_changed") }
                }
        }
        if statusItemWindow == nil,
           let statusBarWindow = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") }) {
            // The status item introspection runs once at launch and can precede the runtime.
            attachStatusItemWindow(statusBarWindow)
        }
        alignPanelToStatusItem(trigger: "panel_attached")
    }

    func attachStatusItem(_ statusItem: NSStatusItem) {
        keepStatusItemWidthStable(statusItem)
        if let button = statusItem.button { iconAnimator.attach(to: button) }
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
        for observer in statusItemObservers { NotificationCenter.default.removeObserver(observer) }
        statusItemWindow = window
        statusItemObservers = observeGeometry(of: window, trigger: "status_item_moved")
        DiagnosticLog.shared.record("interface", "menu_panel_anchor_attached", fields: [
            "anchor_x": String(format: "%.1f", window.frame.minX),
            "anchor_width": String(format: "%.1f", window.frame.width)
        ])
    }

    private func observeGeometry(of window: NSWindow, trigger: String) -> [NSObjectProtocol] {
        [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
         NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.alignPanelToStatusItem(trigger: trigger) }
            }
        }
    }

    /// Keep both axes anchored after SwiftUI presentation and content resizing.
    /// A reused panel can otherwise retain its bottom edge and drift downward
    /// when sections collapse or the list of running apps changes.
    private func alignPanelToStatusItem(trigger: String) {
        guard !isAligningPanel else { return }
        if trigger != "deferred" { scheduleDeferredAlignment() }
        guard let panel = panelWindow, panel.isVisible,
              let anchor = statusItemWindow?.frame, anchor.width > 0,
              let screen = statusItemWindow?.screen ?? panel.screen else { return }
        isAligningPanel = true
        defer { isAligningPanel = false }

        let height = MenuBarPanelPlacement.maximumHeight(anchor: anchor, visibleFrame: screen.visibleFrame)
        if abs(maximumPanelHeight - height) > 0.5 { maximumPanelHeight = height }
        if panelContentHeight > 0 {
            let desiredHeight = min(panelContentHeight, height)
            let contentRect = panel.contentRect(forFrameRect: panel.frame)
            if abs(contentRect.height - desiredHeight) > 0.5 {
                panel.setContentSize(NSSize(width: contentRect.width, height: desiredHeight))
            }
        }
        if trigger == "presented" || trigger == "panel_attached" || trigger == "content_appeared" {
            DiagnosticLog.shared.record("interface", "menu_panel_geometry", fields: [
                "panel_x": String(Int(panel.frame.minX)),
                "panel_y": String(Int(panel.frame.minY)),
                "panel_width": String(Int(panel.frame.width)),
                "panel_height": String(Int(panel.frame.height)),
                "anchor_x": String(format: "%.1f", anchor.minX),
                "anchor_y": String(format: "%.1f", anchor.minY),
                "anchor_width": String(format: "%.1f", anchor.width),
                "visible_frame": NSStringFromRect(screen.visibleFrame),
                "maximum_height": String(Int(height))
            ])
        }
        guard let target = MenuBarPanelPlacement.origin(
            panel: panel.frame, anchor: anchor, visibleFrame: screen.visibleFrame),
            abs(panel.frame.minX - target.x) >= 1.5 || abs(panel.frame.minY - target.y) >= 1.5 else { return }

        DiagnosticLog.shared.record("interface", "menu_panel_realigned", fields: [
            "trigger": trigger,
            "from_x": String(Int(panel.frame.minX)),
            "from_y": String(Int(panel.frame.minY)),
            "to_x": String(Int(target.x)),
            "to_y": String(Int(target.y)),
            "anchor_x": String(format: "%.1f", anchor.minX),
            "panel_width": String(Int(panel.frame.width))
        ])
        panel.setFrameOrigin(target)
    }

    func notePanelContentHeight(_ height: CGFloat) {
        guard abs(panelContentHeight - height) > 0.5 else { return }
        panelContentHeight = height
        DiagnosticLog.shared.record("interface", "menu_panel_content_height", fields: ["height": String(Int(height))])
        scheduleDeferredAlignment()
    }

    private func scheduleDeferredAlignment() {
        guard !alignmentScheduled else { return }
        alignmentScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.alignmentScheduled = false
            self.alignPanelToStatusItem(trigger: "deferred")
        }
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
        alignPanelToStatusItem(trigger: "content_appeared")
        observeRoutePicker()
        if isTemporary {
            noteTemporaryActivity()
        }
    }

    // The system AirPlay popover is another window, so the panel must not time out behind it.
    private func observeRoutePicker() {
        guard routePickerObserver == nil else { return }
        routePickerObserver = NotificationCenter.default.addObserver(
            forName: .airPlayRoutePickerPresentationChanged, object: nil, queue: .main
        ) { [weak self] notification in
            let isOpen = notification.object as? Bool == true
            MainActor.assumeIsolated {
                self?.isRoutePickerOpen = isOpen
                self?.noteTemporaryActivity()
            }
        }
    }

    func noteTemporaryActivity() {
        guard isPresented, isTemporary else { return }
        hideTask?.cancel()
        guard !isPointerInside, !isPressedInside, !isRoutePickerOpen else {
            hideTask = nil
            return
        }

        let duration = temporaryInactivityDuration
        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
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
            temporaryInactivityDuration = Self.inactivityDuration
            hideTask?.cancel()
            hideTask = nil
        } else {
            noteTemporaryActivity()
        }
    }

    /// Touch never hovers, so a press inside the temporary panel keeps it open
    /// until the finger lifts, and a press without hover leaves it up longer.
    private func installPanelPressMonitor() {
        guard panelPressMonitor == nil else { return }
        var mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if #available(macOS 26.0, *) { mask.insert(.mouseCancelled) }
        panelPressMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panelWindow else { return }
                self.setPressedInside(event.type == .leftMouseDown)
            }
            return event
        }
    }

    private func setPressedInside(_ isPressed: Bool) {
        guard isTemporary, isPressedInside != isPressed else { return }
        isPressedInside = isPressed
        if isPressed {
            hideTask?.cancel()
            hideTask = nil
        } else {
            if !isPointerInside { temporaryInactivityDuration = Self.touchInactivityDuration }
            noteTemporaryActivity()
        }
    }

    private func scheduleDismissalCleanup() {
        hideTask?.cancel()
        hideTask = nil
        isPointerInside = false
        isPressedInside = false
        temporaryInactivityDuration = Self.inactivityDuration

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
