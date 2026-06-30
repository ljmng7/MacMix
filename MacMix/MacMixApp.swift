//
//  MacMixApp.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import Sparkle
import SwiftUI

@main
struct MacMixApp: App {
    @StateObject private var audioModel = AudioModel()
    @State private var controlPanelSelection: ControlPanelPage = .settings
    @State private var isRunningFirstLaunchFlow = false
    @AppStorage("MacMix.HasRunFirstLaunchPermissionFlow") private var hasOpenedFirstLaunchAboutPage = false
    @Environment(\.openWindow) private var openWindow

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
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
                updater: updaterController.updater
            )
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: ControlPanelLayout.defaultWindowWidth, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacMix") {
                    controlPanelSelection = .about
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "control-panel")
                    NSApp.activate(ignoringOtherApps: true)
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
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "control-panel")
        NSApp.activate(ignoringOtherApps: true)

        isRunningFirstLaunchFlow = false
    }
}

private struct MenuBarVolumeIcon: View {
    @ObservedObject var state: OutputAudioState

    var body: some View {
        Image(systemName: state.menuBarSymbolName)
    }
}
