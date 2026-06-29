//
//  MacMixApp.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import SwiftUI

@main
struct MacMixApp: App {
    @StateObject private var audioModel = AudioModel()
    @State private var controlPanelSelection: ControlPanelPage = .settings
    @State private var isRunningFirstLaunchFlow = false
    @AppStorage("MacMix.HasRunFirstLaunchPermissionFlow") private var hasRunFirstLaunchPermissionFlow = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MacMixPanel(audioModel: audioModel)
        } label: {
            MenuBarVolumeIcon(state: audioModel.outputState)
                .task {
                    await runFirstLaunchPermissionFlowIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Control Panel", id: "control-panel") {
            MacMixControlPanel(audioModel: audioModel, selection: $controlPanelSelection)
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
        }
    }

    @MainActor
    private func runFirstLaunchPermissionFlowIfNeeded() async {
        guard !hasRunFirstLaunchPermissionFlow,
              !isRunningFirstLaunchFlow else {
            return
        }

        isRunningFirstLaunchFlow = true
        hasRunFirstLaunchPermissionFlow = true
        controlPanelSelection = .about
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "control-panel")
        NSApp.activate(ignoringOtherApps: true)

        try? await Task.sleep(nanoseconds: 500_000_000)
        audioModel.requestSystemAudioPermission()
        isRunningFirstLaunchFlow = false
    }
}

private struct MenuBarVolumeIcon: View {
    @ObservedObject var state: OutputAudioState

    var body: some View {
        Image(systemName: state.menuBarSymbolName)
    }
}
