//
//  MacMixApp.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import MacMixStudio
import MenuBarExtraAccess
import Observation
import SwiftUI

@main
struct MacMixApp: App {
    @NSApplicationDelegateAdaptor(MacMixApplicationDelegate.self) private var appDelegate
    @State private var runtime: MacMixRuntime?
    @State private var controlPanelSelection: ControlPanelPage = .panel
    @State private var isPresentingIntro = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private let edition = Edition.shared

    init() {
        _ = DiagnosticFeedbackModel.shared
        if !Edition.shared.requiresLaunchAuthorization {
            _runtime = State(initialValue: MacMixRuntime(entitlements: Edition.shared.entitlements))
            Edition.shared.runtimeDidStart()
        }
    }

    private var entitlements: any EntitlementProvider { edition.entitlements }

    private var menuBarIsInserted: Binding<Bool> {
        Binding(get: { runtime?.menuBarVisibility.isVisible ?? false },
                set: { runtime?.menuBarVisibility.isVisible = $0 })
    }

    private var menuBarIsPresented: Binding<Bool> {
        Binding(get: { runtime?.menuBarPanelCoordinator.isPresented ?? false },
                set: { runtime?.menuBarPanelCoordinator.isPresented = $0 })
    }

    var body: some Scene {
        let _ = configureApplicationDelegate()

        MenuBarExtra(isInserted: menuBarIsInserted) {
            if let runtime {
                MenuBarPanelContent(
                    coordinator: runtime.menuBarPanelCoordinator,
                    audioModel: runtime.audioModel,
                    nowPlayingModel: runtime.nowPlayingModel,
                    hasStudioAccess: entitlements.hasStudioAccess
                )
            }
        } label: {
            if let runtime {
                MenuBarVolumeIcon(state: runtime.audioModel.outputState, sceneSymbol: menuBarSceneSymbol)
                    .accessibilityLabel(Text(verbatim: "MacMix"))
                    .onChange(of: entitlements.hasStudioAccess, initial: true) { previous, enabled in
                        edition.entitlementDidChange(from: previous, to: enabled)
                        runtime.updateStudioAccess(enabled)
                    }
                    .task {
                        edition.interfaceDidAppear()
                        await entitlements.refreshEntitlement()
                        runtime.updateStudioAccess(entitlements.hasStudioAccess)
                        await presentIntroIfNeeded()
                    }
                    .task(id: edition.hasCompletedFirstRunIntro) {
                        guard edition.hasCompletedFirstRunIntro else { return }
                        await runtime.systemAudioPermissionStatus.runPeriodicRefreshLoop()
                    }
            }
        }
        .menuBarExtraAccess(
            isPresented: menuBarIsPresented
        )
        .menuBarExtraStyle(.window)

        Window("Control Panel", id: "control-panel") {
            if let runtime {
                MacMixControlPanel(
                    audioModel: runtime.audioModel,
                    systemAudioPermissionStatus: runtime.systemAudioPermissionStatus,
                    selection: $controlPanelSelection,
                    menuBarVisibility: runtime.menuBarVisibility,
                    hasStudioAccess: entitlements.hasStudioAccess,
                    inputDeviceLock: runtime.inputDeviceLock,
                    systemVolumeTakeover: runtime.systemVolumeTakeover
                )
                    .environment(\.hasStudioAccess, entitlements.hasStudioAccess)
                    .background(SceneWindowAnchor { view in
                        runtime.menuBarPanelCoordinator.mainWindow = view.window
                        if let window = view.window { runtime.audioModel.observeAudioInterfaceWindow(window) }
                    })
                    .onChange(of: entitlements.hasStudioAccess, initial: true) { previous, enabled in
                        edition.entitlementDidChange(from: previous, to: enabled)
                        runtime.updateStudioAccess(enabled)
                    }
                    .onAppear {
                        edition.interfaceDidAppear()
                        DiagnosticLog.shared.record("interface", "main_window_opened")
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        DiagnosticLog.shared.record("interface", "main_window_closed")
                        if !DiagnosticFeedbackModel.shared.isWindowOpen {
                            NSApp.setActivationPolicy(runtime.menuBarVisibility.isVisible ? .accessory : .regular)
                        }
                    }
            } else {
                PendingLaunchWindowPlaceholder()
            }
        }
        .defaultSize(width: ControlPanelLayout.windowWidth, height: 700)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .sidebar) {}

            CommandGroup(replacing: .appInfo) {
                Button("About MacMix") {
                    controlPanelSelection = .about
                    showControlPanel()
                }
                .disabled(runtime == nil)
            }

            CommandGroup(after: .appInfo) {
                Divider()

                Button("Settings") {
                    controlPanelSelection = .settings
                    showControlPanel()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(runtime == nil)

                if runtime != nil, let items = edition.appMenuItems() {
                    items
                }
            }
        }

        Window("Send Feedback", id: DiagnosticFeedbackView.windowID) {
            if let runtime {
                DiagnosticFeedbackView(model: .shared)
                    .environment(\.hasStudioAccess, entitlements.hasStudioAccess)
                    .onAppear {
                        DiagnosticFeedbackModel.shared.isWindowOpen = true
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        DiagnosticFeedbackModel.shared.isWindowOpen = false
                        if runtime.menuBarPanelCoordinator.mainWindow?.isVisible != true {
                            NSApp.setActivationPolicy(runtime.menuBarVisibility.isVisible ? .accessory : .regular)
                        }
                    }
            } else {
                PendingLaunchWindowPlaceholder()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        edition.scenes(EditionSceneContext(
            systemAudioPermissionStatus: runtime?.systemAudioPermissionStatus,
            showControlPanel: {
                controlPanelSelection = .panel
                showControlPanel()
            },
            restoreActivationPolicy: {
                guard let runtime else { return }
                NSApp.setActivationPolicy(runtime.menuBarVisibility.isVisible ? .accessory : .regular)
            }
        ))
    }

    @MainActor
    private func presentIntroIfNeeded() async {
        guard let introWindowID = edition.pendingIntroWindowID, !isPresentingIntro else {
            return
        }

        isPresentingIntro = true
        controlPanelSelection = .panel
        dismissWindow(id: "control-panel")
        openWindow(id: introWindowID)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        await Task.yield()
        isPresentingIntro = false
    }

    private func showControlPanel() {
        guard runtime != nil else {
            edition.showLaunchAuthorization()
            return
        }
        NSApp.setActivationPolicy(.regular)
        if let introWindowID = edition.pendingIntroWindowID {
            dismissWindow(id: "control-panel")
            openWindow(id: introWindowID)
        } else {
            openWindow(id: "control-panel")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private var menuBarSceneSymbol: String? {
        guard let runtime else { return nil }
        guard entitlements.hasStudioAccess, runtime.audioModel.sceneStore.showsMenuBarScene,
              let id = runtime.audioModel.activeSceneID else { return nil }
        return runtime.audioModel.sceneStore.presets.first(where: { $0.id == id })?.symbol
    }

    private func configureApplicationDelegate() {
        let edition = edition
        appDelegate.beginLaunchAuthorization = edition.requiresLaunchAuthorization ? {
            Task { @MainActor in
                await edition.authorizeLaunch {
                    guard runtime == nil else { return }
                    runtime = MacMixRuntime(entitlements: edition.entitlements)
                    edition.runtimeDidStart()
                    NSApp.setActivationPolicy(runtime?.menuBarVisibility.isVisible == true ? .accessory : .regular)
                    if runtime?.menuBarVisibility.isVisible == false { showControlPanel() }
                }
            }
        } : nil

        let openWindow = openWindow
        let dismissWindow = dismissWindow
        let introWindowID = edition.pendingIntroWindowID
        appDelegate.openPrimaryInterface = {
            guard runtime != nil else {
                edition.showLaunchAuthorization()
                return
            }
            NSApp.setActivationPolicy(.regular)
            if let introWindowID {
                dismissWindow(id: "control-panel")
                openWindow(id: introWindowID)
            } else {
                openWindow(id: "control-panel")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
private final class MacMixRuntime {
    let audioModel: AudioModel
    let nowPlayingModel: NowPlayingModel
    let systemAudioPermissionStatus: SystemAudioPermissionStatusModel
    let inputDeviceLock: InputDeviceLockController
    let systemVolumeTakeover: SystemVolumeTakeoverModel
    let menuBarVisibility: MenuBarVisibilityModel
    let menuBarPanelCoordinator: MenuBarPanelCoordinator

    func updateStudioAccess(_ enabled: Bool) {
        audioModel.updateSceneAccess(enabled)
        audioModel.updateEqualizerAccess(enabled)
        audioModel.updateOutputRoutingAccess(enabled)
        inputDeviceLock.updateProAccess(enabled)
        systemVolumeTakeover.updateStudioAccess(enabled)
    }

    init(entitlements: any EntitlementProvider) {
        let defaults = UserDefaults.standard
        let audioModel = AudioModel()
        // Launch authorization, when a build needs it, has already resolved the entitlement.
        // Restore EQ now, rather than waiting for a menu-bar or window view to appear.
        audioModel.updateEqualizerAccess(entitlements.hasStudioAccess)
        let nowPlayingModel = NowPlayingModel()
        let systemAudioPermissionStatus = SystemAudioPermissionStatusModel()
        let inputDeviceLock = InputDeviceLockController(
            defaults: defaults,
            currentDeviceUID: { [weak audioModel] in
                audioModel?.currentInputDevice?.uid
            },
            availableDeviceUIDs: { [weak audioModel] in
                audioModel?.inputState.devices.map(\.uid) ?? []
            },
            selectDevice: { [weak audioModel] uid in
                audioModel?.restoreInputDevice(uid: uid)
            }
        )
        let systemVolumeTakeover = SystemVolumeTakeoverModel(
            audioModel: audioModel,
            defaults: defaults
        )
        let menuBarPanelCoordinator = MenuBarPanelCoordinator()
        audioModel.sceneDidSwitch = { [weak menuBarPanelCoordinator] feedback in
            guard defaults.object(forKey: MenuBarPreference.showsMenuBarItem) as? Bool ?? true else { return }
            menuBarPanelCoordinator?.presentSceneFeedback(feedback)
        }
        systemVolumeTakeover.menuBarPanelCoordinator = menuBarPanelCoordinator
        audioModel.inputDevicesDidChange = { [weak inputDeviceLock] in
            inputDeviceLock?.inputDevicesDidChange()
        }
        audioModel.inputDeviceUserSelectionDidChange = { [weak inputDeviceLock] uid in
            inputDeviceLock?.userSelectedDevice(uid: uid)
        }
        let isMenuBarVisible = defaults.object(forKey: MenuBarPreference.showsMenuBarItem) as? Bool ?? true

        DiagnosticFeedbackModel.shared.snapshot = { [weak audioModel, weak systemAudioPermissionStatus] in
            var state = audioModel?.diagnosticSnapshot() ?? [:]
            state["studioAccess"] = String(entitlements.hasStudioAccess)
            state["permissionCachedAuthorized"] = String(systemAudioPermissionStatus?.isAuthorized ?? false)
            return state
        }
        DiagnosticFeedbackModel.shared.configuration = { [weak audioModel, weak systemAudioPermissionStatus] in
            var capture = audioModel?.diagnosticConfiguration() ?? .init()
            capture.summary["studioAccess"] = String(entitlements.hasStudioAccess)
            capture.summary["permissionCachedAuthorized"] = String(systemAudioPermissionStatus?.isAuthorized ?? false)
            return capture
        }
        DiagnosticFeedbackModel.shared.identification = { [weak audioModel] in
            audioModel?.diagnosticIdentificationCandidates() ?? []
        }
        DiagnosticFeedbackModel.shared.affectedItems = { [weak audioModel] in
            audioModel?.diagnosticAffectedItems() ?? []
        }
        DiagnosticFeedbackModel.shared.mixerSnapshot = { id in
            AppAudioMixer.shared.requestDiagnosticSnapshot(diagnosticID: id)
        }
        self.audioModel = audioModel
        self.nowPlayingModel = nowPlayingModel
        self.systemAudioPermissionStatus = systemAudioPermissionStatus
        self.inputDeviceLock = inputDeviceLock
        self.systemVolumeTakeover = systemVolumeTakeover

        self.menuBarVisibility = MenuBarVisibilityModel(isVisible: isMenuBarVisible, defaults: defaults)
        self.menuBarPanelCoordinator = menuBarPanelCoordinator
        if !isMenuBarVisible {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

}

enum MenuBarPreference {
    static let showsMenuBarItem = "MacMix.ShowsMenuBarItem"
}

@MainActor
@Observable
final class MenuBarVisibilityModel {
    private let defaults: UserDefaults

    var isVisible: Bool {
        didSet {
            guard isVisible != oldValue else {
                return
            }

            defaults.set(isVisible, forKey: MenuBarPreference.showsMenuBarItem)
            if !isVisible {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    init(
        isVisible: Bool,
        defaults: UserDefaults
    ) {
        self.isVisible = isVisible
        self.defaults = defaults
    }
}

@MainActor
private final class MacMixApplicationDelegate: NSObject, NSApplicationDelegate {
    var beginLaunchAuthorization: (() -> Void)? {
        didSet { if hasFinishedLaunching { requestLaunchAuthorizationIfReady() } }
    }
    private var hasFinishedLaunching = false
    private let diagnosticTermination = DiagnosticTerminationCoordinator()
    private var hasRequestedLaunchAuthorization = false

    private func requestLaunchAuthorizationIfReady() {
        guard !hasRequestedLaunchAuthorization, let beginLaunchAuthorization else { return }
        hasRequestedLaunchAuthorization = true
        beginLaunchAuthorization()
    }

    var openPrimaryInterface: (() -> Void)? {
        didSet {
            guard shouldOpenPrimaryInterfaceWhenReady,
                  let openPrimaryInterface else {
                return
            }

            shouldOpenPrimaryInterfaceWhenReady = false
            DispatchQueue.main.async {
                openPrimaryInterface()
            }
        }
    }

    private var shouldOpenPrimaryInterfaceWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Keep MacMix available from the Dock when its windows are closed."
        )

        hasFinishedLaunching = true
        if Edition.shared.requiresLaunchAuthorization {
            requestLaunchAuthorizationIfReady()
            return
        }

        let defaults = UserDefaults.standard
        let isMenuBarVisible = defaults.object(forKey: MenuBarPreference.showsMenuBarItem) as? Bool ?? true
        if !isMenuBarVisible {
            requestPrimaryInterface()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else {
            return true
        }

        requestPrimaryInterface()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if diagnosticTermination.didFinish { return .terminateNow }
        guard !diagnosticTermination.isPending else { return .terminateLater }
        DiagnosticActions.shared.flush()
        DiagnosticLog.shared.record("application", "exit", fields: ["normal": "true"])
        diagnosticTermination.begin(flush: {
            await DiagnosticLog.shared.flush()
        }, completion: { [weak sender] in
            sender?.reply(toApplicationShouldTerminate: true)
        })
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestPrimaryInterface() {
        guard let openPrimaryInterface else {
            shouldOpenPrimaryInterfaceWhenReady = true
            return
        }

        DispatchQueue.main.async {
            openPrimaryInterface()
        }
    }

}

private struct MenuBarVolumeIcon: View {
    let state: OutputAudioState
    var sceneSymbol: String?

    var body: some View {
        Image(systemName: sceneSymbol ?? state.menuBarSymbolName)
    }
}
