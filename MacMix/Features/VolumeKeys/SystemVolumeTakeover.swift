import AppKit
import MacMixStudio
import Observation

enum SystemVolumePanelMode: String, CaseIterable, Identifiable {
    case systemVolume
    case outputPanel
    case fullPanel

    var id: Self { self }
}

enum SystemVolumeTakeoverPreference {
    static let isEnabled = "MacMix.Pro.SystemVolumeTakeover.IsEnabled"
    static let panelMode = "MacMix.Pro.SystemVolumeTakeover.PanelMode"
    static let mixShortcut = "MacMix.Pro.MixVolumeShortcut.Modifier"
}

@MainActor
@Observable
final class SystemVolumeTakeoverModel {
    var mixShortcutModifier: MixVolumeShortcutModifier {
        didSet {
            defaults.set(mixShortcutModifier.rawValue, forKey: SystemVolumeTakeoverPreference.mixShortcut)
            interceptor?.mixShortcutModifier = mixShortcutModifier
        }
    }
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: SystemVolumeTakeoverPreference.isEnabled)
            reconcile(promptForPermission: isEnabled)
        }
    }

    var panelMode: SystemVolumePanelMode {
        didSet {
            guard panelMode != oldValue else { return }
            defaults.set(panelMode.rawValue, forKey: SystemVolumeTakeoverPreference.panelMode)
        }
    }

    private(set) var hasAccessibilityPermission: Bool

    @ObservationIgnored weak var menuBarPanelCoordinator: MenuBarPanelCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let audioModel: AudioModel
    @ObservationIgnored private var interceptor: SystemVolumeKeyInterceptor!
    @ObservationIgnored private var hasStudioAccess = false

    init(
        audioModel: AudioModel,
        defaults: UserDefaults = .standard
    ) {
        self.audioModel = audioModel
        self.defaults = defaults
        mixShortcutModifier = defaults.string(forKey: SystemVolumeTakeoverPreference.mixShortcut)
            .flatMap(MixVolumeShortcutModifier.init(rawValue:)) ?? .disabled
        isEnabled = defaults.bool(
            forKey: SystemVolumeTakeoverPreference.isEnabled
        )
        panelMode = defaults.string(
            forKey: SystemVolumeTakeoverPreference.panelMode
        ).flatMap(SystemVolumePanelMode.init(rawValue:)) ?? .systemVolume
        hasAccessibilityPermission = SystemVolumeKeyInterceptor
            .hasAccessibilityPermission
        interceptor = SystemVolumeKeyInterceptor(onAction: { [weak self] action in
            self?.handle(action)
        }, onAppAction: { [weak self] index, action in
            self?.handleApp(index: index, action: action)
        })
        interceptor.mixShortcutModifier = mixShortcutModifier
    }

    func updateStudioAccess(_ hasAccess: Bool) {
        guard hasStudioAccess != hasAccess else { return }
        hasStudioAccess = hasAccess
        reconcile(promptForPermission: false)
    }

    func refreshAccessibilityPermission() {
        hasAccessibilityPermission = SystemVolumeKeyInterceptor
            .hasAccessibilityPermission
        reconcile(promptForPermission: false)
    }

    func requestAccessibilityPermission() {
        hasAccessibilityPermission = SystemVolumeKeyInterceptor
            .requestAccessibilityPermission()
        reconcile(promptForPermission: false)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func reconcile(promptForPermission: Bool) {
        guard isEnabled, hasStudioAccess else {
            interceptor?.stop()
            menuBarPanelCoordinator?.dismissTemporaryPanel()
            return
        }

        hasAccessibilityPermission = SystemVolumeKeyInterceptor
            .hasAccessibilityPermission
        if !hasAccessibilityPermission, promptForPermission {
            hasAccessibilityPermission = SystemVolumeKeyInterceptor
                .requestAccessibilityPermission()
        }

        guard hasAccessibilityPermission else {
            interceptor.stop()
            return
        }

        if !interceptor.start() {
            hasAccessibilityPermission = false
        }
    }

    private func handle(_ action: SystemVolumeKeyAction) {
        guard isEnabled, hasStudioAccess else {
            reconcile(promptForPermission: false)
            return
        }

        // Set the panel mode before mutating audio state. The menu bar label
        // observes that same state and may cause MenuBarExtra to rebuild
        // immediately, so the temporary content must already be selected.
        menuBarPanelCoordinator?.presentTemporary(mode: panelMode)

        switch action {
        case .increase:
            changeVolume(by: 1.0 / 16.0)
        case .decrease:
            changeVolume(by: -1.0 / 16.0)
        case .toggleMute:
            audioModel.toggleSystemOutputMute()
        }
    }

    private func changeVolume(by delta: Double) {
        guard let volume = audioModel.outputState.systemVolume else {
            return
        }
        audioModel.setSystemOutputVolume(max(0, min(1, volume + delta)))
    }

    private func handleApp(index: Int, action: SystemVolumeKeyAction) {
        guard isEnabled, hasStudioAccess, mixShortcutModifier != .disabled, (0..<9).contains(index),
              audioModel.outputAppsState.apps.indices.contains(index) else { return }
        let app = audioModel.outputAppsState.apps[index]
        menuBarPanelCoordinator?.presentAppVolume(app)
        switch action {
        case .toggleMute: audioModel.toggleAppMute(app)
        case .increase, .decrease:
            audioModel.setAppVolume(MixVolumeStep.volume(app.volume, action: action), for: app)
        }
    }
}
