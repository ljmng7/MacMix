//
//  MacMixApp.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import Observation
import Sparkle
import SwiftUI

@main
struct MacMixApp: App {
    @NSApplicationDelegateAdaptor(MacMixApplicationDelegate.self) private var appDelegate
    @State private var audioModel = AudioModel()
    @State private var menuBarVisibility: MenuBarVisibilityModel
    @State private var controlPanelSelection: ControlPanelPage = .settings
    @State private var isRunningFirstLaunchFlow = false
    @AppStorage("MacMix.HasRunFirstLaunchPermissionFlow") private var hasOpenedFirstLaunchAboutPage = false
    @Environment(\.openWindow) private var openWindow

    private let updaterController: SPUStandardUpdaterController

    init() {
        let defaults = UserDefaults.standard
        let isMenuBarVisible = defaults.object(forKey: MenuBarPreference.showsMenuBarItem) as? Bool ?? true
        _menuBarVisibility = State(
            initialValue: MenuBarVisibilityModel(
                isVisible: isMenuBarVisible,
                defaults: defaults
            )
        )

        if !isMenuBarVisible {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        let _ = configureApplicationDelegate()

        MenuBarExtra(isInserted: $menuBarVisibility.isVisible) {
            MacMixPanel(audioModel: audioModel)
        } label: {
            MenuBarVolumeIcon(state: audioModel.outputState)
                .task {
                    await openAboutPageOnFirstLaunchIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Control Panel", id: "control-panel") {
            MacMixControlPanel(
                audioModel: audioModel,
                selection: $controlPanelSelection,
                updater: updaterController.updater,
                menuBarVisibility: menuBarVisibility
            )
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(menuBarVisibility.isVisible ? .accessory : .regular)
                }
        }
        .defaultSize(width: ControlPanelLayout.defaultWindowWidth, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacMix") {
                    controlPanelSelection = .about
                    showControlPanel()
                }
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }

    @MainActor
    private func openAboutPageOnFirstLaunchIfNeeded() async {
        guard !hasOpenedFirstLaunchAboutPage,
              !isRunningFirstLaunchFlow else {
            return
        }

        isRunningFirstLaunchFlow = true
        hasOpenedFirstLaunchAboutPage = true
        controlPanelSelection = .about
        showControlPanel()

        isRunningFirstLaunchFlow = false
    }

    private func showControlPanel() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "control-panel")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureApplicationDelegate() {
        let openWindow = openWindow
        appDelegate.openControlPanel = {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "control-panel")
            NSApp.activate(ignoringOtherApps: true)
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

    init(isVisible: Bool, defaults: UserDefaults) {
        self.isVisible = isVisible
        self.defaults = defaults
    }
}

@MainActor
private final class MacMixApplicationDelegate: NSObject, NSApplicationDelegate {
    var openControlPanel: (() -> Void)? {
        didSet {
            guard shouldOpenControlPanelWhenReady,
                  let openControlPanel else {
                return
            }

            shouldOpenControlPanelWhenReady = false
            DispatchQueue.main.async {
                openControlPanel()
            }
        }
    }

    private var shouldOpenControlPanelWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Keep MacMix available from the Dock when its windows are closed."
        )

        let defaults = UserDefaults.standard
        let isMenuBarVisible = defaults.object(forKey: MenuBarPreference.showsMenuBarItem) as? Bool ?? true
        if !isMenuBarVisible {
            requestControlPanel()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else {
            return true
        }

        requestControlPanel()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestControlPanel() {
        guard let openControlPanel else {
            shouldOpenControlPanelWhenReady = true
            return
        }

        DispatchQueue.main.async {
            openControlPanel()
        }
    }
}

private struct MenuBarVolumeIcon: View {
    let state: OutputAudioState

    var body: some View {
        Image(systemName: state.menuBarSymbolName)
    }
}
