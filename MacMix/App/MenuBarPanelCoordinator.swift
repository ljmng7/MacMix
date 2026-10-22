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
        panelWindow = window
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
