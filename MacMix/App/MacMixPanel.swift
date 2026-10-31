//
//  MacMixPanel.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import Combine
import MacMixStudio
import MenuBarExtraAccess
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct MacMixPanel: View {
    let audioModel: AudioModel
    let nowPlayingModel: NowPlayingModel
    let hasStudioAccess: Bool
    @AppStorage(PanelVisibilityPreference.showsNowPlaying) private var showsNowPlayingInPanel = true
    @AppStorage(PanelVisibilityPreference.showsOutput) private var showsOutputInPanel = true
    @AppStorage(PanelVisibilityPreference.showsMix) private var showsMixInPanel = true
    @AppStorage(PanelVisibilityPreference.showsInput) private var showsInputInPanel = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let showsNowPlayingSection = hasStudioAccess
            && showsNowPlayingInPanel
            && !nowPlayingModel.sessions.isEmpty
        let showsSceneRow = hasStudioAccess && audioModel.sceneStore.showsInPanel
            && !audioModel.sceneStore.presets.isEmpty

        VStack(spacing: 12) {
            if showsSceneRow {
                ScenePanelSelectionRow(audio: audioModel, trailingEdgeExtension: 14, compact: true)
                    .padding(.bottom, -12)
            }
            if showsNowPlayingSection {
                NowPlayingSection(model: nowPlayingModel, topContentInset: showsSceneRow ? 0 : 16)
            }

            SystemVolumeSection(audioModel: audioModel)

            Divider()

            if showsOutputInPanel {
                OutputSection(audioModel: audioModel)
            }

            if showsOutputInPanel && showsMixInPanel {
                Divider()
            }

            if showsMixInPanel {
                MixSection(audioModel: audioModel)
            }

            if (showsOutputInPanel || showsMixInPanel) && showsInputInPanel {
                Divider()
            }

            if showsInputInPanel {
                InputSection(audioModel: audioModel)
            }

            if showsOutputInPanel || showsMixInPanel || showsInputInPanel {
                Divider()
            }

            // Keep Quit clear of the full-width Open Main Window target for touch.
            HStack(spacing: 16) {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "control-panel")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                } label: {
                    Label("Open Main Window", systemImage: "macwindow")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit MacMix", systemImage: "power")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.medium))
                        // Match the notification mute button's frame so both icons share a center line.
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .fixedSize()
                .help("Quit MacMix")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, showsSceneRow || showsNowPlayingSection ? 0 : 16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MenuBarPanelContent: View {
    let coordinator: MenuBarPanelCoordinator
    let audioModel: AudioModel
    let nowPlayingModel: NowPlayingModel
    let hasStudioAccess: Bool
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system

    var body: some View {
        Group {
            if coordinator.isTemporary, let feedback = coordinator.sceneFeedback {
                TemporarySceneFeedbackContent(feedback: feedback)
            } else if coordinator.isTemporary, let app = coordinator.volumeApp {
                TemporaryAppVolumeContent(app: app, audioModel: audioModel)
                    .onChange(of: app.volume) { coordinator.noteTemporaryActivity() }
                    .onChange(of: app.isMuted) { coordinator.noteTemporaryActivity() }
                    .onChange(of: audioModel.outputAppsState.apps.map(\.id)) {
                        if !audioModel.outputAppsState.apps.contains(where: { $0.id == app.id }) {
                            coordinator.dismissTemporaryPanel()
                        }
                    }
            } else {
            switch coordinator.mode {
            case .systemVolume:
                TemporarySystemVolumeContent(audioModel: audioModel)
            case .outputPanel:
                TemporaryOutputPanelContent(audioModel: audioModel)
            case .fullPanel:
                MacMixPanel(
                    audioModel: audioModel,
                    nowPlayingModel: nowPlayingModel,
                    hasStudioAccess: hasStudioAccess
                )
            }
            }
        }
        .modifier(
            TemporaryPanelActivityModifier(
                systemVolume: audioModel.outputState.systemVolume,
                onPointerInsideChange: coordinator.setPointerInside,
                onActivity: coordinator.noteTemporaryActivity
            )
        )
        .tint(accentColor.resolvedColor(hasStudioAccess: hasStudioAccess))
        .environment(\.hasStudioAccess, hasStudioAccess)
        .frame(width: coordinator.isTemporary && coordinator.sceneFeedback != nil ? 240 : 320)
        .introspectMenuBarExtraWindow { window in
            coordinator.attachPanelWindow(window)
            audioModel.observeAudioInterfaceWindow(window)
        }
        .onAppear {
            coordinator.panelDidAppear()
        }
    }
}

private struct TemporarySceneFeedbackContent: View {
    let feedback: ScenePanelFeedback

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: feedback.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(SceneAppearance.color(feedback.color))
                    .frame(width: 32)
                Spacer(minLength: 0)
            }
            VStack(spacing: 2) {
                SceneFadingName(name: feedback.name, maximumWidth: 112)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(feedback.isEnabled ? "On" : "Off")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 40)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct TemporarySystemVolumeContent: View {
    let audioModel: AudioModel

    var body: some View {
        SystemVolumeSection(
            audioModel: audioModel,
            title: .deviceName(
                audioModel.outputState.currentDevice?.name
                    ?? String(localized: "Output")
            )
        )
        .padding(14)
    }
}

private struct TemporaryAppVolumeContent: View {
    let app: AudioAppState
    let audioModel: AudioModel
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var enablesBoost = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { audioModel.toggleAppMute(app) } label: {
                    AppIcon(image: app.icon, isMuted: app.isMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.isMuted ? Text("Unmute") : Text("Mute"))
                .help(app.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
                Text(app.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            VolumeSliderRow(
                leadingIcon: app.isMuted ? "speaker.slash.fill" : "speaker.fill",
                trailingIcon: "speaker.wave.3.fill",
                percentage: app.volume,
                value: Binding(get: { app.volume }, set: { audioModel.setAppVolume($0, for: app) }),
                isMuted: app.isMuted,
                maximumVolume: min(enablesBoost ? 2 : 1, audioModel.maximumVolume(for: app.bundleID)),
                onLeadingIconTap: { audioModel.toggleAppMute(app) }
            )
        }
        .padding(14)
    }
}

private struct TemporaryOutputPanelContent: View {
    let audioModel: AudioModel
    @AppStorage(PanelVisibilityPreference.showsMix) private var showsMixInPanel = true

    var body: some View {
        VStack(spacing: 12) {
            SystemVolumeSection(audioModel: audioModel)

            Divider()

            OutputSection(audioModel: audioModel)

            if showsMixInPanel {
                Divider()

                MixSection(audioModel: audioModel)
            }
        }
        .padding(14)
    }
}

private struct TemporaryPanelActivityModifier: ViewModifier {
    let systemVolume: Double?
    let onPointerInsideChange: (Bool) -> Void
    let onActivity: () -> Void

    func body(content: Content) -> some View {
        content
            .onHover(perform: onPointerInsideChange)
            .onChange(of: systemVolume) {
                onActivity()
            }
    }
}

private enum PanelVisibilityPreference {
    static let showsNowPlaying = "MacMix.ShowsNowPlayingInPanel"
    static let showsOutput = "MacMix.ShowsOutputInPanel"
    static let showsInput = "MacMix.ShowsInputInPanel"
    static let showsMix = "MacMix.ShowsMixInPanel"
}

enum AccessoryDetailsVisibilityPreference {
    static let showsAccessoryDetails = "MacMix.ShowsAccessoryDetails"
}

private enum MacMixTint {
    static let yellow = Color(nsColor: .systemYellow)
    static let gray = Color(nsColor: .systemGray)
}

struct MacMixControlPanel: View {
    let audioModel: AudioModel
    let systemAudioPermissionStatus: SystemAudioPermissionStatusModel
    @Binding var selection: ControlPanelPage
    let menuBarVisibility: MenuBarVisibilityModel
    let hasStudioAccess: Bool
    let inputDeviceLock: InputDeviceLockController
    let systemVolumeTakeover: SystemVolumeTakeoverModel
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @State private var searchText = ""
    @AppStorage(ThemePreference.mainInterfaceBackgroundMaterial) private var backgroundMaterial: MainInterfaceBackgroundMaterial = .standard

    private var resolvedAccentColor: Color {
        accentColor.resolvedColor(hasStudioAccess: hasStudioAccess)
    }

    private var resolvedBackgroundMaterial: MainInterfaceBackgroundMaterial {
        backgroundMaterial.resolved(hasStudioAccess: hasStudioAccess)
    }

    var body: some View {
        Edition.shared.controlPanel(AnyView(content))
    }

    private var content: some View {
        NavigationSplitView {
            ControlPanelSidebar(
                selection: $selection,
                searchText: $searchText,
                audioModel: audioModel,
                accentColor: resolvedAccentColor,
                backgroundMaterial: resolvedBackgroundMaterial,
                hasStudioAccess: hasStudioAccess
            )
        } detail: {
            ControlPanelDetail(
                selection: selection,
                audioModel: audioModel,
                systemAudioPermissionStatus: systemAudioPermissionStatus,
                menuBarVisibility: menuBarVisibility,
                accentColor: $accentColor,
                backgroundMaterial: $backgroundMaterial,
                hasStudioAccess: hasStudioAccess,
                inputDeviceLock: inputDeviceLock,
                systemVolumeTakeover: systemVolumeTakeover
            )
        }
        .tint(resolvedAccentColor)
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(
            minWidth: ControlPanelLayout.windowWidth,
            idealWidth: ControlPanelLayout.windowWidth,
            maxWidth: ControlPanelLayout.windowWidth,
            maxHeight: .infinity
        )
        .modifier(
            MainInterfaceWindowBackgroundModifier(
                style: resolvedBackgroundMaterial.windowBackgroundStyle
            )
        )
        .environment(\.hasStudioAccess, hasStudioAccess)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            systemVolumeTakeover.refreshAccessibilityPermission()
        }
    }
}

enum ControlPanelLayout {
    static let windowWidth: CGFloat = 770
    static let sidebarWidth: CGFloat = 200
    static let detailMinWidth: CGFloat = windowWidth - sidebarWidth
    static let detailIdealWidth: CGFloat = detailMinWidth
    static let mixSliderMinimumWidth: CGFloat = 240
}

private struct ControlPanelSidebar: View {
    @Binding var selection: ControlPanelPage
    @Binding var searchText: String
    let audioModel: AudioModel
    let accentColor: Color
    let backgroundMaterial: MainInterfaceBackgroundMaterial
    let hasStudioAccess: Bool

    private struct Item: Identifiable {
        let id: ControlPanelPage
        let title: LocalizedStringResource
        let symbolName: String
        let color: Color
        var usesAsset = false
    }

    private var items: [Item] {
        [
            Item(id: .panel, title: "Panel", symbolName: "slider.horizontal.3", color: accentColor),
            Item(id: .settings, title: "Settings", symbolName: "gearshape", color: Color(nsColor: .systemGray)),
            Item(id: .scenes, title: "Scene", symbolName: "app.3.stack.3d", color: .purple, usesAsset: true),
            Item(id: .blacklist, title: "Blacklist", symbolName: "xmark.octagon", color: Color(nsColor: .systemRed)),
            Item(id: .about, title: "About", symbolName: "info.circle", color: Color(nsColor: .systemGreen))
        ]
    }

    var body: some View {
        Group {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                List(selection: $selection) {
                    ForEach(items) { item in
                        ControlPanelSidebarRow(
                            title: item.title,
                            symbolName: item.symbolName,
                            color: item.color,
                            usesAsset: item.usesAsset
                        )
                        .tag(item.id)
                    }
                }
            } else {
                ControlPanelSearchResults(
                    audioModel: audioModel,
                    query: searchText,
                    accentColor: accentColor
                ) { page in
                    selection = page
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar)
        .listStyle(.sidebar)
        .scrollContentBackground(backgroundMaterial.usesBlur ? .hidden : .automatic)
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(ControlPanelLayout.sidebarWidth)
    }
}

private struct ControlPanelSearchResults: View {
    let audioModel: AudioModel
    let query: String
    let accentColor: Color
    let onSelect: (ControlPanelPage) -> Void

    private struct Entry: Identifiable {
        let id: String
        let title: String
    }

    private struct ResultGroup: Identifiable {
        let id: ControlPanelPage
        let title: LocalizedStringResource
        let entries: [Entry]
    }

    // Use the same localization keys as the controls, so searches match the
    // language shown in the app. Dynamic names come from the live audio model.
    private var resultGroups: [ResultGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pages: [(ControlPanelPage, LocalizedStringResource, [LocalizedStringResource])] = [
            (.panel, "Panel", [
                "System Volume", "Output", "Input", "Input Volume", "Mix",
                "Show in Panel", "Listening Mode", "Spatial Audio",
                "Enable \(2.0, format: .percent.precision(.fractionLength(0))) Volume"
            ]),
            (.settings, "Settings", [
                "General", "Open at Login", "Show in Menu Bar", "Appearance", "Theme Color",
                "Main Window Background Material", "Default", "More Transparent", "Advanced",
                "Show Now Playing Media in Menu Bar",
                "Show Battery, Listening Mode, and Spatial Audio", "Custom EQ",
                LocalizedStringResource("Multi-Device Output", table: "AppOutputRouting"), "Lock Input Device",
                "Take Over System Volume Controls", "System Volume Only", "Output Panel",
                "Full Panel", "Open Accessibility Settings", "Accessibility Permission Required"
            ]),
            (.scenes, "Scene", [
                "Scene Presets", "New Scene", "Default", "Output", "Input", "Mix",
                "Show at Top of Panel", "Show Scene in Menu Bar Icon",
                "Automatically Launch Mixed Apps", "1–9 activate scenes in order. 0 turns scenes off."
            ]),
            (.blacklist, "Blacklist", [
                "Current", "Add Selected to Blacklist", "Remove Selected from Blacklist"
            ]),
            (.about, "About", [
                "Version", "System Audio Recording", "Go to Authorize",
                "Privacy Information", "Feedback", "Logs and Feedback", "Show in Finder", "Clear Logs",
                "Made with 🫶 by Jazmín",
                "Mixing needs System Audio Recording permission because macOS requires this permission before an app can process another app's audio. MacMix uses it only for local real-time mixing when you adjust per-app volume, and does not record, save, or upload audio."
            ])
        ]

        return pages.compactMap { page, title, labels in
            var entries = ([title] + labels).map {
                Entry(id: "label:\($0.key)", title: String(localized: $0))
            }
            switch page {
            case .panel:
                entries += audioModel.outputState.devices.map { Entry(id: "output:\($0.uid)", title: $0.name) }
                entries += audioModel.inputState.devices.map { Entry(id: "input:\($0.uid)", title: $0.name) }
                entries += audioModel.outputAppsState.apps.map { Entry(id: "app:\($0.id)", title: $0.name) }
            case .scenes:
                for (index, scene) in audioModel.sceneStore.presets.enumerated() {
                    let name = scene.displayName(at: index)
                    entries.append(Entry(id: "scene:\(scene.id)", title: name))
                    if let output = scene.output {
                        entries.append(Entry(id: "scene:\(scene.id):output", title: "\(name) · \(output.name)"))
                    }
                    if let input = scene.input {
                        entries.append(Entry(id: "scene:\(scene.id):input", title: "\(name) · \(input.name)"))
                    }
                    entries += scene.apps.map { Entry(id: "scene:\(scene.id):app:\($0.id)", title: "\(name) · \($0.name)") }
                }
            case .blacklist:
                entries += audioModel.outputAppsState.apps.map { Entry(id: "current:\($0.id)", title: $0.name) }
                entries += audioModel.audioAppBlacklistState.apps.map { Entry(id: "blocked:\($0.id)", title: $0.name) }
            case .about:
                entries.append(Entry(id: "contact:MacMix", title: "MacMix"))
                entries += Edition.shared.aboutSearchLabels.map {
                    Entry(id: "label:\($0.key)", title: String(localized: $0))
                }
            case .settings:
                break
            }
            let matches = entries.filter { $0.title.localizedStandardContains(query) }
            return matches.isEmpty ? nil : ResultGroup(id: page, title: title, entries: matches)
        }
    }

    var body: some View {
        let groups = resultGroups
        List {
            ForEach(groups) { group in
                ForEach(group.entries) { entry in
                    Button {
                        onSelect(group.id)
                    } label: {
                        ControlPanelSearchResultRow(
                            title: entry.title,
                            pageTitle: group.title,
                            page: group.id,
                            accentColor: accentColor
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .controlSize(.small)
            }
        }
    }

}

private struct ControlPanelSearchResultRow: View {
    let title: String
    let pageTitle: LocalizedStringResource
    let page: ControlPanelPage
    let accentColor: Color

    private var symbolName: String {
        switch page {
        case .panel: "slider.horizontal.3"
        case .settings: "gearshape"
        case .scenes: "app.3.stack.3d"
        case .blacklist: "xmark.octagon"
        case .about: "info.circle"
        }
    }

    private var color: Color {
        switch page {
        case .panel: accentColor
        case .settings: Color(nsColor: .systemGray)
        case .scenes: .purple
        case .blacklist: Color(nsColor: .systemRed)
        case .about: Color(nsColor: .systemGreen)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ControlPanelSidebarIcon(symbolName: symbolName, color: color, usesAsset: page == .scenes)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center]
                        + NSFont.preferredFont(forTextStyle: .body).capHeight / 2
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pageTitle)
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ControlPanelSidebarRow: View {
    let title: LocalizedStringResource
    let symbolName: String
    let color: Color
    var usesAsset = false

    var body: some View {
        HStack(spacing: 10) {
            ControlPanelSidebarIcon(symbolName: symbolName, color: color, usesAsset: usesAsset)

            Text(title)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct ControlPanelSidebarIcon: View {
    let symbolName: String
    let color: Color
    let usesAsset: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.76), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 22, height: 22)
                .overlay {
                    (usesAsset ? Image(symbolName) : Image(systemName: symbolName))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)

    }
}

private struct ControlPanelDetail: View {
    let selection: ControlPanelPage
    let audioModel: AudioModel
    let systemAudioPermissionStatus: SystemAudioPermissionStatusModel
    let menuBarVisibility: MenuBarVisibilityModel
    @Binding var accentColor: ThemeAccentColor
    @Binding var backgroundMaterial: MainInterfaceBackgroundMaterial
    let hasStudioAccess: Bool
    let inputDeviceLock: InputDeviceLockController
    let systemVolumeTakeover: SystemVolumeTakeoverModel

    private var resolvedBackgroundMaterial: MainInterfaceBackgroundMaterial {
        backgroundMaterial.resolved(hasStudioAccess: hasStudioAccess)
    }

    var body: some View {
        Group {
            switch selection {
            case .panel:
                ControlPanelPanelPage(audioModel: audioModel)
            case .scenes:
                AudioScenesPage(audioModel: audioModel, isStudioEnabled: hasStudioAccess)
            case .blacklist:
                ControlPanelBlacklistPage(
                    audioModel: audioModel,
                    isStudioEnabled: hasStudioAccess
                )
            case .settings:
                ControlPanelSettingsPage(
                    audioModel: audioModel,
                    menuBarVisibility: menuBarVisibility,
                    accentColor: $accentColor,
                    backgroundMaterial: $backgroundMaterial,
                    hasStudioAccess: hasStudioAccess,
                    inputDeviceLock: inputDeviceLock,
                    systemVolumeTakeover: systemVolumeTakeover
                )
            case .about:
                ControlPanelAboutPage(
                    audioModel: audioModel,
                    systemAudioPermissionStatus: systemAudioPermissionStatus
                )
            }
        }
        .navigationSplitViewColumnWidth(
            min: ControlPanelLayout.detailMinWidth,
            ideal: ControlPanelLayout.detailIdealWidth
        )
        .scrollContentBackground(resolvedBackgroundMaterial.usesBlur ? .hidden : .automatic)
    }
}

enum ControlPanelPage: Hashable {
    case scenes
    case panel
    case blacklist
    case settings
    case about
}

private struct ControlPanelPanelPage: View {
    let audioModel: AudioModel
    @AppStorage(PanelVisibilityPreference.showsOutput) private var showsOutputInPanel = true
    @AppStorage(PanelVisibilityPreference.showsMix) private var showsMixInPanel = true
    @AppStorage(PanelVisibilityPreference.showsInput) private var showsInputInPanel = true
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var enables200PercentVolume = false

    private var maximumAppVolume: Double {
        enables200PercentVolume ? 2 : 1
    }

    var body: some View {
        Form {
            Section {
                ControlPanelVolumeRow(title: "System Volume") {
                    SystemVolumeControl(
                        state: audioModel.outputState,
                        expandsToFill: true,
                        onVolumeChange: audioModel.setSystemOutputVolume,
                        onToggleMute: audioModel.toggleSystemOutputMute
                    )
                }
            }

            Section {
                Toggle("Show in Panel", isOn: $showsOutputInPanel)
                    .accessibilityLabel("Show output in panel")
                    .toggleStyle(.switch)

                if showsOutputInPanel {
                    let state = audioModel.outputState
                    if state.devices.isEmpty && state.nearbyAccessories.isEmpty {
                        EmptyRow(iconName: "questionmark.circle", title: "No available devices")
                    } else {
                        ForEach(state.orderedRows(for: state.devices)) { row in
                            switch row {
                            case let .device(device):
                                AudioDeviceRow(
                                    device: device,
                                    battery: state.batteryByDeviceUID[device.uid],
                                    accessoryControls: state.accessoryControlsByDeviceUID[device.uid],
                                    reservesAccessoryControlSpace: true,
                                    onSelect: audioModel.selectOutputDevice,
                                    onSetListeningMode: audioModel.setListeningMode,
                                    onSetSpatialAudioMode: audioModel.setSpatialAudioMode
                                )
                            case let .nearby(accessory):
                                NearbyAccessoryRow(
                                    accessory: accessory,
                                    state: state,
                                    onConnect: audioModel.connectNearbyAccessory
                                )
                            }
                        }
                    }
                }
            } header: {
                Text("Output")
            }

            Section {
                Toggle("Show in Panel", isOn: $showsMixInPanel)
                    .accessibilityLabel("Show mix in panel")
                    .toggleStyle(.switch)

                if showsMixInPanel {
                    EqualizerAwareBoostToggle(isOn: $enables200PercentVolume,
                                              isBlocked: audioModel.equalizerStore.isFeatureActive)

                    if audioModel.outputAppsState.needsSystemAudioPermission {
                        PermissionRequestRow(action: audioModel.requestSystemAudioPermission)
                    } else if audioModel.outputAppsState.apps.isEmpty {
                        EmptyRow(iconName: "app.dashed", title: "No apps are playing audio")
                    } else {
                        ForEach(audioModel.outputAppsState.apps) { app in
                            AppVolumeRow(
                                app: app,
                                maximumVolume: maximumAppVolume,
                                audioModel: audioModel,
                                layout: .controlPanel,
                                onToggleMute: audioModel.toggleAppMute,
                                onVolumeChange: { volume, app in
                                    audioModel.setAppVolume(volume, for: app)
                                }
                            )
                        }
                    }
                }
            } header: {
                Text("Mix")
            }

            Section {
                Toggle("Show in Panel", isOn: $showsInputInPanel)
                    .accessibilityLabel("Show input in panel")
                    .toggleStyle(.switch)

                if showsInputInPanel {
                    if audioModel.inputState.devices.isEmpty {
                        EmptyRow(iconName: "questionmark.circle", title: "No available devices")
                    } else {
                        ForEach(audioModel.inputState.devices) { device in
                            AudioDeviceRow(
                                device: device,
                                battery: nil,
                                accessoryControls: nil,
                                reservesAccessoryControlSpace: false,
                                onSelect: audioModel.selectInputDevice
                            )
                        }
                    }

                    ControlPanelVolumeRow(title: "Input Volume") {
                        InputVolumeControl(
                            state: audioModel.inputState,
                            showsPercentage: true,
                            expandsToFill: true,
                            onVolumeChange: audioModel.setInputVolume,
                            onToggleMute: audioModel.toggleInputMute
                        )
                    }
                }
            } header: {
                Text("Input")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScenePanelSelectionRow(audio: audioModel)
                .padding(.horizontal, 16)
        }
        .frame(
            minWidth: ControlPanelLayout.detailMinWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .navigationTitle("Panel")
        .toolbar {
            ToolbarItem(id: "quit", placement: .primaryAction) {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit MacMix", systemImage: "power")
                }
                .labelStyle(.iconOnly)
                .help("Quit MacMix")
                .tint(nil)
                .foregroundStyle(.primary)
            }
        }
        .onChange(of: enables200PercentVolume) { _, isEnabled in
            if !isEnabled {
                audioModel.clampAppVolumesToUnity()
            }
        }
    }
}

private struct ControlPanelBlacklistPage: View {
    let audioModel: AudioModel
    let isStudioEnabled: Bool
    @State private var isEditing = false
    @State private var selectedCurrentAppIDs: Set<String> = []
    @State private var selectedBlacklistedAppIDs: Set<String> = []

    private static let listTransitionAnimation = Animation.smooth(duration: 0.22)

    var body: some View {
        VStack(spacing: 0) {
            Form {
                CurrentAudioAppsBlacklistSection(
                    apps: audioModel.outputAppsState.apps,
                    isStudioEnabled: isStudioEnabled,
                    isEditing: isEditing,
                    selectedAppIDs: selectedCurrentAppIDs,
                    onToggleSelection: toggleCurrentAppSelection,
                    onAdd: addToBlacklist
                )
                BlacklistedAudioAppsSection(
                    apps: audioModel.audioAppBlacklistState.apps,
                    isEditing: isEditing,
                    selectedAppIDs: selectedBlacklistedAppIDs,
                    onToggleSelection: toggleBlacklistedAppSelection,
                    onRemove: removeFromBlacklist,
                    onChooseApps: chooseAppsForBlacklist
                )
                .disabled(!isStudioEnabled)
            }
            .formStyle(.grouped)
        }
        .frame(
            minWidth: ControlPanelLayout.detailMinWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .navigationTitle("Blacklist")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Button(action: addSelectedAppsToBlacklist) {
                        Label("Add Selected to Blacklist", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .tint(.red)
                    .disabled(!isStudioEnabled || selectedCurrentAppIDs.isEmpty)
                    .help("Add Selected to Blacklist")

                    Button(action: removeSelectedAppsFromBlacklist) {
                        Label("Remove Selected from Blacklist", systemImage: "minus")
                    }
                    .labelStyle(.iconOnly)
                    .tint(.green)
                    .disabled(!isStudioEnabled || selectedBlacklistedAppIDs.isEmpty)
                    .help("Remove Selected from Blacklist")
                }

                Button {
                    isEditing.toggle()
                    if !isEditing {
                        selectedCurrentAppIDs.removeAll()
                        selectedBlacklistedAppIDs.removeAll()
                    }
                } label: {
                    if isEditing {
                        Text(
                            "Done",
                            comment: "Toolbar button that finishes editing the audio app blacklist."
                        )
                    } else {
                        Text(
                            "Edit",
                            comment: "Toolbar button that enters batch editing for the audio app blacklist."
                        )
                    }
                }
                .disabled(!isStudioEnabled)
            }
        }
    }

    private func addSelectedAppsToBlacklist() {
        guard isStudioEnabled else { return }
        withAnimation(Self.listTransitionAnimation) {
            audioModel.addAppsToBlacklist(appIDs: selectedCurrentAppIDs)
            selectedCurrentAppIDs.removeAll()
        }
    }

    private func removeSelectedAppsFromBlacklist() {
        guard isStudioEnabled else { return }
        withAnimation(Self.listTransitionAnimation) {
            audioModel.removeAppsFromBlacklist(appIDs: selectedBlacklistedAppIDs)
            selectedBlacklistedAppIDs.removeAll()
        }
    }

    private func toggleCurrentAppSelection(_ appID: String) {
        guard isStudioEnabled else { return }
        if !selectedCurrentAppIDs.insert(appID).inserted {
            selectedCurrentAppIDs.remove(appID)
        }
    }

    private func toggleBlacklistedAppSelection(_ appID: String) {
        guard isStudioEnabled else { return }
        if !selectedBlacklistedAppIDs.insert(appID).inserted {
            selectedBlacklistedAppIDs.remove(appID)
        }
    }

    private func addToBlacklist(_ app: AudioAppState) {
        guard isStudioEnabled else { return }
        withAnimation(Self.listTransitionAnimation) {
            selectedCurrentAppIDs.remove(app.id)
            audioModel.addAppToBlacklist(app)
        }
    }

    private func removeFromBlacklist(_ app: AudioAppBlacklistEntry) {
        guard isStudioEnabled else { return }
        withAnimation(Self.listTransitionAnimation) {
            selectedBlacklistedAppIDs.remove(app.id)
            audioModel.removeAppFromBlacklist(app)
        }
    }

    private func chooseAppsForBlacklist(in window: NSWindow?) {
        guard isStudioEnabled else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            withAnimation(Self.listTransitionAnimation) {
                audioModel.addApplicationsToBlacklist(at: panel.urls)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

private struct CurrentAudioAppsBlacklistSection: View {
    let apps: [AudioAppState]
    let isStudioEnabled: Bool
    let isEditing: Bool
    let selectedAppIDs: Set<String>
    let onToggleSelection: (String) -> Void
    let onAdd: (AudioAppState) -> Void

    var body: some View {
        Section {
            if apps.isEmpty {
                EmptyRow(
                    iconName: "app.dashed",
                    title: "No current audio apps"
                )
                .padding(.vertical, 1)
                .transition(.opacity)
            } else {
                ForEach(apps) { app in
                    CurrentAudioAppBlacklistRow(
                        name: app.name,
                        icon: app.icon,
                        isEditing: isEditing,
                        isSelected: selectedAppIDs.contains(app.id),
                        onToggleSelection: {
                            onToggleSelection(app.id)
                        },
                        onAdd: {
                            onAdd(app)
                        }
                    )
                    .disabled(!isStudioEnabled)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        } header: {
            StudioPromptHeader(placement: .blacklistHeader, title: "Current")
        }
    }
}

private struct BlacklistedAudioAppsSection: View {
    let apps: [AudioAppBlacklistEntry]
    let isEditing: Bool
    let selectedAppIDs: Set<String>
    let onToggleSelection: (String) -> Void
    let onRemove: (AudioAppBlacklistEntry) -> Void
    let onChooseApps: (NSWindow?) -> Void
    @State private var pickerAnchor: NSView?

    var body: some View {
        Section {
            if apps.isEmpty {
                EmptyRow(
                    iconName: "checkmark.shield.fill",
                    title: "No blacklisted apps"
                )
                .padding(.vertical, 1)
                .transition(.opacity)
            } else {
                ForEach(apps) { app in
                    BlacklistedAudioAppRow(
                        name: app.name,
                        icon: app.icon,
                        isEditing: isEditing,
                        isSelected: selectedAppIDs.contains(app.id),
                        onToggleSelection: {
                            onToggleSelection(app.id)
                        },
                        onRemove: {
                            onRemove(app)
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            Button("Choose Other App…") {
                onChooseApps(pickerAnchor?.window)
            }
            .foregroundStyle(.primary)
            .tint(.secondary)
            .background(SceneWindowAnchor { pickerAnchor = $0 })
        } header: {
            Text("Blacklist")
        } footer: {
            Edition.shared.studioPrompt(.blacklistFooter)
        }
    }
}

private struct CurrentAudioAppBlacklistRow: View {
    let name: String
    let icon: NSImage?
    let isEditing: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                AudioAppBlacklistSelectionButton(
                    isSelected: isSelected,
                    action: onToggleSelection
                )
            }

            AppIcon(image: icon, isMuted: false)

            Text(name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Blacklist")
            .help("Add to Blacklist")
        }
        .padding(.vertical, 3)
    }
}

private struct BlacklistedAudioAppRow: View {
    let name: String
    let icon: NSImage?
    let isEditing: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                AudioAppBlacklistSelectionButton(
                    isSelected: isSelected,
                    action: onToggleSelection
                )
            }

            AppIcon(image: icon, isMuted: false)

            Text(name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: onRemove) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.green, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from Blacklist")
            .help("Remove from Blacklist")
        }
        .padding(.vertical, 3)
    }
}

private struct AudioAppBlacklistSelectionButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DrawSwapSymbol(name: isSelected ? "checkmark.circle.fill" : "circle") {
                Image(systemName: $0)
                    .font(.title3)
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color.secondary
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle Selection")
    }
}

private struct ControlPanelVolumeRow<Control: View>: View {
    let title: LocalizedStringKey
    private let control: Control

    init(title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .lineLimit(1)
                .frame(width: 105, alignment: .leading)

            control
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ControlPanelSettingsPage: View {
    let audioModel: AudioModel
    let menuBarVisibility: MenuBarVisibilityModel
    @Binding var accentColor: ThemeAccentColor
    @Binding var backgroundMaterial: MainInterfaceBackgroundMaterial
    let hasStudioAccess: Bool
    let inputDeviceLock: InputDeviceLockController
    let systemVolumeTakeover: SystemVolumeTakeoverModel
    @AppStorage(PanelVisibilityPreference.showsNowPlaying) private var showsNowPlayingInPanel = true
    @AppStorage(AccessoryDetailsVisibilityPreference.showsAccessoryDetails) private var showsAccessoryDetails = true

    var body: some View {
        Form {
            Section {
                OpenAtLoginToggle()
                ShowInMenuBarToggle(menuBarVisibility: menuBarVisibility)
            } header: {
                StudioPromptHeader(placement: .settingsHeader, title: "General")
            }

            Section {
                ThemeColorPicker(selection: $accentColor)
                if #available(macOS 15.0, *) {
                    MainInterfaceBackgroundMaterialSlider(selection: $backgroundMaterial)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Appearance")
                    Edition.shared.studioPrompt(.requirementBadge)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!hasStudioAccess)

            AdvancedSettingsSection(
                audioModel: audioModel,
                showsNowPlayingInPanel: $showsNowPlayingInPanel,
                showsAccessoryDetails: $showsAccessoryDetails,
                inputDeviceLock: inputDeviceLock,
                systemVolumeTakeover: systemVolumeTakeover
            )
            .disabled(!hasStudioAccess)

        }
        .formStyle(.grouped)
        .frame(
            minWidth: ControlPanelLayout.detailMinWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .navigationTitle("Settings")
    }
}

@available(macOS 15.0, *)
private struct MainInterfaceBackgroundMaterialSlider: View {
    @Binding var selection: MainInterfaceBackgroundMaterial
    @State private var draftSelection: MainInterfaceBackgroundMaterial

    init(selection: Binding<MainInterfaceBackgroundMaterial>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        LabeledContent {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "app.fill")
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                materialSlider
                    .frame(width: ControlPanelLayout.mixSliderMinimumWidth)

                Image(systemName: "app")
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .sensoryFeedback(.alignment, trigger: draftSelection.sliderPosition)
        } label: {
            Text(
                "Main Window Background Material",
                comment: "Settings row for choosing the background material used by both columns of the main window."
            )
        }
        .task(id: draftSelection) {
            // AppStorage posts synchronously. Leave the native slider's binding
            // callback before updating the window and its outline-backed List.
            await Task.yield()
            guard !Task.isCancelled, selection != draftSelection else { return }
            selection = draftSelection
        }
        .onChange(of: selection) { _, newValue in
            if draftSelection != newValue {
                draftSelection = newValue
            }
        }
    }

    @ViewBuilder
    private var materialSlider: some View {
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            MaterialSliderWithNativeTicks(value: $draftSelection.sliderPosition)
        } else {
            MaterialSliderWithLegacyTicks(value: $draftSelection.sliderPosition)
        }
    }
}

@available(macOS 26.0, *)
private struct MaterialSliderWithNativeTicks: View {
    @Binding var value: Double

    var body: some View {
        Slider(
            value: $value,
            in: 0...5,
            step: 1,
            label: {
                EmptyView()
            },
            tick: { value in
                switch value {
                case 0:
                    SliderTick(value) {
                        Text(
                            "Default",
                            comment: "Background material option that keeps the existing main window appearance."
                        )
                    }
                case 5:
                    SliderTick(value) {
                        Text(
                            "More Transparent",
                            comment: "Label for the most transparent end of the main window material slider."
                        )
                    }
                default:
                    SliderTick(value)
                }
            }
        )
        .accessibilityLabel(
            Text(
                "Main Window Background Material",
                comment: "Accessibility label for the main window material slider."
            )
        )
    }
}

@available(macOS 15.0, *)
private struct MaterialSliderWithLegacyTicks: View {
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 3) {
            Slider(
                value: $value,
                in: 0...5,
                step: 1,
                label: {
                    EmptyView()
                }
            )
            .accessibilityLabel(
                Text(
                    "Main Window Background Material",
                    comment: "Accessibility label for the main window material slider."
                )
            )

            HStack {
                Text(
                    "Default",
                    comment: "Background material option that keeps the existing main window appearance."
                )
                Spacer()
                Text(
                    "More Transparent",
                    comment: "Label for the most transparent end of the main window material slider."
                )
            }
            .font(.caption)
        }
    }
}

private struct AdvancedSettingsSection: View {
    let audioModel: AudioModel
    @Binding var showsNowPlayingInPanel: Bool
    @Binding var showsAccessoryDetails: Bool
    let inputDeviceLock: InputDeviceLockController
    let systemVolumeTakeover: SystemVolumeTakeoverModel

    var body: some View {
        @Bindable var inputDeviceLock = inputDeviceLock
        @Bindable var systemVolumeTakeover = systemVolumeTakeover

        Section {
            Toggle(isOn: $showsNowPlayingInPanel) {
                Text(
                    "Show Now Playing Media in Menu Bar",
                    comment: "Settings toggle that controls whether current media sessions appear in the menu bar menu."
                )
            }
            .toggleStyle(.switch)

            Toggle(isOn: $showsAccessoryDetails) {
                Text(
                    "Show Battery, Listening Mode, and Spatial Audio",
                    comment: "Settings toggle that controls whether output device rows show battery status and expandable listening mode and Spatial Audio controls."
                )
            }
            .toggleStyle(.switch)

            CustomEqualizerSettingsToggle(audioModel: audioModel)
            MultiOutputSettingsToggle(audioModel: audioModel)
        } header: {
            HStack(spacing: 6) {
                Text(
                    "Advanced",
                    comment: "Settings section for advanced application preferences."
                )
                Edition.shared.studioPrompt(.requirementBadge)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }

        Section {
            Toggle(isOn: $inputDeviceLock.isEnabled) {
                Text(
                    "Lock Input Device",
                    comment: "Pro settings toggle that prevents newly connected input devices from replacing the user's selected input device."
                )
            }
            .toggleStyle(.switch)

            Toggle(isOn: $systemVolumeTakeover.isEnabled) {
                Text(
                    "Take Over System Volume Controls",
                    comment: "Pro settings toggle that lets MacMix handle the system volume media keys."
                )
            }
            .toggleStyle(.switch)

            if systemVolumeTakeover.isEnabled {
                SystemVolumePanelModePicker(
                    selection: $systemVolumeTakeover.panelMode
                )

                if !systemVolumeTakeover.hasAccessibilityPermission {
                    SystemVolumeTakeoverPermissionRow(
                        onOpenSettings: {
                            systemVolumeTakeover.requestAccessibilityPermission()
                            systemVolumeTakeover.openAccessibilitySettings()
                        }
                    )
                }
            }
            MixVolumeShortcutPicker(model: systemVolumeTakeover)
        } footer: {
            Text("Hold the modifier, a number from 1–9, and a system volume key to control the first nine apps in mixer order.")
        }
        .animation(.smooth(duration: 0.2), value: systemVolumeTakeover.isEnabled)
    }
}

private struct SystemVolumePanelModePicker: View {
    @Binding var selection: SystemVolumePanelMode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(SystemVolumePanelMode.allCases) { mode in
                SystemVolumePanelModeOption(
                    mode: mode,
                    isSelected: selection == mode,
                    action: { selection = mode }
                )
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SystemVolumePanelModeOption: View {
    let mode: SystemVolumePanelMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                GeometryReader { proxy in
                    Image(decorative: mode.previewImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .top
                        )
                }
                .frame(width: 72, height: 96)
                .clipShape(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color(nsColor: .separatorColor).opacity(0.55),
                            lineWidth: 1
                        )
                }

                Text(mode.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title2)
                .foregroundStyle(isSelected ? .green : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
        .accessibilityValue(
            isSelected
                ? Text("Selected", comment: "Accessibility value for the selected temporary panel mode.")
                : Text("Not Selected", comment: "Accessibility value for an unselected temporary panel mode.")
        )
    }
}

private struct SystemVolumeTakeoverPermissionRow: View {
    let onOpenSettings: () -> Void

    var body: some View {
        LabeledContent {
            Button(
                "Open Accessibility Settings",
                action: onOpenSettings
            )
        } label: {
            Label(
                "Accessibility Permission Required",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }
}

private extension SystemVolumePanelMode {
    var previewImageName: String {
        switch self {
        case .systemVolume:
            "SystemVolumeOnlyPreview"
        case .outputPanel:
            "OutputPanelPreview"
        case .fullPanel:
            "FullPanelPreview"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .systemVolume:
            "System Volume Only"
        case .outputPanel:
            "Output Panel"
        case .fullPanel:
            "Full Panel"
        }
    }
}

private struct ThemeColorPicker: View {
    @Binding var selection: ThemeAccentColor

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Theme Color")

            Spacer(minLength: 24)

            HStack(spacing: 4) {
                ForEach(ThemeAccentColor.allCases) { accentColor in
                    ThemeColorSwatch(
                        accentColor: accentColor,
                        isSelected: selection == accentColor
                    ) {
                        selection = accentColor
                    }
                }
            }
        }
    }
}

private struct ThemeColorSwatch: View {
    let accentColor: ThemeAccentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Circle()
                    .fill(accentColor.color)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .stroke(
                                isSelected ? accentColor.color : .clear,
                                lineWidth: 3
                            )
                            .padding(-3)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accentColor.localizedName))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Text(accentColor.localizedName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(width: 34)
    }
}

private struct ShowInMenuBarToggle: View {
    let menuBarVisibility: MenuBarVisibilityModel

    var body: some View {
        @Bindable var menuBarVisibility = menuBarVisibility

        Toggle(
            "Show in Menu Bar",
            isOn: $menuBarVisibility.isVisible
        )
        .toggleStyle(.switch)
    }
}

private struct PanelVisibilityHeader: View {
    let title: LocalizedStringKey
    let accessibilityLabel: LocalizedStringKey
    @Binding var isVisible: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.semibold))

            Spacer()

            Toggle(accessibilityLabel, isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct ControlPanelAboutPage: View {
    let audioModel: AudioModel
    let systemAudioPermissionStatus: SystemAudioPermissionStatusModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                AboutVersionRow()
                Edition.shared.aboutSettingsRows()
            } header: {
                Group {
                    if let header = Edition.shared.aboutHeader() {
                        header
                    } else {
                        AboutBrandHeader()
                    }
                }
                .padding(.vertical, 16)
                .foregroundStyle(.primary)
            }

            Section {
                PermissionAccessRow(
                    isAuthorized: systemAudioPermissionStatus.isAuthorized,
                    action: audioModel.openSystemAudioRecordingSettingsForAuthorization
                )

                Text("Mixing needs System Audio Recording permission because macOS requires this permission before an app can process another app's audio. MacMix uses it only for local real-time mixing when you adjust per-app volume, and does not record, save, or upload audio.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy Information")
            }

            DiagnosticAboutSection()

            Section {
                EmptyView()
            } footer: {
                VStack(spacing: 16) {
                    Edition.shared.aboutFooterLinks()
                    AboutMadeWithLoveFooter()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: ControlPanelLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("About")
        .toolbar {
            ToolbarItem(id: "feedback", placement: .primaryAction) {
                Button { openWindow(id: DiagnosticFeedbackView.windowID) } label: {
                    Label("Feedback", systemImage: "exclamationmark.bubble")
                }
                .labelStyle(.iconOnly)
                .help("Feedback")
                .tint(nil)
                .foregroundStyle(.primary)
                .disabled(DiagnosticFeedbackModel.shared.isWorking)
            }
            if let button = Edition.shared.aboutToolbarButton() {
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(id: "edition", placement: .primaryAction) {
                    button
                }
            }
        }
    }
}

struct AboutBrandHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            AboutAppIcon(name: colorScheme == .dark ? "AboutAppIconDark" : "AboutAppIconDefault")

            Text(verbatim: "MacMix")
                .font(.title.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct AboutAppIcon: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: 112, height: 112)
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.22), radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)
    }
}

private struct AboutVersionRow: View {
    var body: some View {
        LabeledContent {
            Text(verbatim: Self.versionText)
        } label: {
            Text("Version")
        }
    }

    private static var versionText: String {
        let version = Edition.shared.displayVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        let text: String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            text = "\(version) (\(build))"
        case let (.some(version), .none):
            text = version
        case let (.none, .some(build)):
            text = build
        case (.none, .none):
            return "—"
        }
        return architectureName.map { "\(text) (\($0))" } ?? text
    }

    // Read from the executable itself, so it names the package that is actually installed.
    private static var architectureName: String? {
        let architectures = Set((Bundle.main.executableArchitectures ?? []).map(\.intValue))
        switch (architectures.contains(NSBundleExecutableArchitectureARM64),
                architectures.contains(NSBundleExecutableArchitectureX86_64)) {
        case (true, true): return "Universal"
        case (true, false): return "Apple Silicon"
        case (false, true): return "Intel"
        case (false, false): return nil
        }
    }
}

struct StarOnGitHubLink: View {
    private let repositoryURL = URL(string: "https://github.com/ljmng7/MacMix")!

    var body: some View {
        Link(destination: repositoryURL) {
            HStack(spacing: 8) {
                Text("Star me on GitHub🤗")
                    .font(.body.weight(.semibold))

                Image("GitHub")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 76, height: 28)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.secondary.opacity(0.14), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Star me on GitHub🤗")
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AboutMadeWithLoveFooter: View {
    var body: some View {
        Text("Made with 🫶 by Jazmín")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

private struct PermissionAccessRow: View {
    let isAuthorized: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("System Audio Recording")

            Spacer(minLength: 16)

            if isAuthorized {
                Text("Authorized")
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text("Go to Authorize")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OpenAtLoginToggle: View {
    @State private var isEnabled = OpenAtLoginToggle.currentStatus
    @State private var isUpdating = false
    @AppStorage("MacMix.HasConfiguredOpenAtLoginDefault") private var hasConfiguredDefault = false

    var body: some View {
        Toggle(
            "Open at Login",
            isOn: Binding(
                get: { isEnabled },
                set: updateLoginItem
            )
        )
        .toggleStyle(.switch)
        .disabled(isUpdating)
        .onAppear {
            enableByDefaultIfNeeded()
        }
    }

    private func enableByDefaultIfNeeded() {
        guard !hasConfiguredDefault else {
            isEnabled = Self.currentStatus
            return
        }

        hasConfiguredDefault = true

        do {
            try SMAppService.mainApp.register()
        } catch {
            hasConfiguredDefault = false
        }

        isEnabled = Self.currentStatus
    }

    private func updateLoginItem(_ shouldEnable: Bool) {
        isUpdating = true
        defer {
            isEnabled = Self.currentStatus
            isUpdating = false
        }

        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return
        }
    }

    private static var currentStatus: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            true
        default:
            false
        }
    }
}

private enum SystemVolumeSectionTitle {
    case systemVolume
    case deviceName(String)
}

private struct SystemVolumeSection: View {
    let audioModel: AudioModel
    var title: SystemVolumeSectionTitle = .systemVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch title {
            case .systemVolume:
                HStack {
                    Text("System Volume")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    NotificationSoundMuteButton(controller: audioModel.notificationSound)
                }
            case let .deviceName(name):
                Text(name)
                    .font(.headline.weight(.semibold))
            }

            SystemVolumeControl(
                state: audioModel.outputState,
                onVolumeChange: audioModel.setSystemOutputVolume,
                onToggleMute: audioModel.toggleSystemOutputMute
            )
        }
    }
}

private struct NotificationSoundMuteButton: View {
    let controller: NotificationSoundController

    var body: some View {
        let label = controller.isMuted
            ? String(localized: "Unmute Notification Sounds")
            : String(localized: "Mute Notification Sounds")
        Button(action: controller.toggleMute) {
            DrawSwapSymbol(name: controller.isMuted ? "bell.slash.fill" : "bell.fill") {
                SliderSymbol(name: $0, isMuted: controller.isMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}

private struct OutputSection: View {
    let audioModel: AudioModel
    @AppStorage("MacMix.OutputSectionExpanded") private var isOutputExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CollapsibleHeader(title: "Output", isExpanded: $isOutputExpanded)

            if isOutputExpanded {
                OutputDeviceGroup(
                    state: audioModel.outputState,
                    onSelect: audioModel.selectOutputDevice,
                    onSetListeningMode: audioModel.setListeningMode,
                    onSetSpatialAudioMode: audioModel.setSpatialAudioMode,
                    onConnectNearby: audioModel.connectNearbyAccessory
                )
            }
        }
    }
}

private struct InputSection: View {
    let audioModel: AudioModel
    @AppStorage("MacMix.InputSectionExpanded") private var isInputExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CollapsibleHeader(title: "Input", isExpanded: $isInputExpanded)

            if isInputExpanded {
                InputDeviceGroup(
                    state: audioModel.inputState,
                    onSelect: audioModel.selectInputDevice
                )

                InputVolumeControl(
                    state: audioModel.inputState,
                    onVolumeChange: audioModel.setInputVolume,
                    onToggleMute: audioModel.toggleInputMute
                )
            }
        }
    }
}

private struct SystemVolumeControl: View {
    let state: OutputAudioState
    var expandsToFill = false
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VolumeSliderRow(
            leadingIcon: state.isSystemMuted ? "speaker.slash.fill" : "speaker.fill",
            trailingIcon: "speaker.wave.3.fill",
            percentage: state.systemVolume,
            value: Binding(
                get: { state.systemVolume ?? 0 },
                set: onVolumeChange
            ),
            isEnabled: state.systemVolume != nil,
            isMuted: state.isSystemMuted,
            expandsToFill: expandsToFill,
            onLeadingIconTap: onToggleMute
        )
    }
}

private struct OutputDeviceGroup: View {
    let state: OutputAudioState
    let onSelect: (AudioDevice) -> Void
    let onSetListeningMode: (ListeningMode, AudioDevice) -> Void
    let onSetSpatialAudioMode: (SpatialAudioMode, AudioDevice) -> Void
    let onConnectNearby: (NearbyAudioAccessory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.selectionDevices.isEmpty && state.nearbyAccessories.isEmpty {
                EmptyRow(iconName: "questionmark.circle", title: "No available devices")
            } else {
                ForEach(state.orderedRows(for: state.selectionDevices)) { row in
                    switch row {
                    case let .device(device):
                        AudioDeviceRow(
                            device: device,
                            battery: state.batteryByDeviceUID[device.uid],
                            accessoryControls: state.accessoryControlsByDeviceUID[device.uid],
                            reservesAccessoryControlSpace: true,
                            accessoryControlsPresentation: .menuBarPanel,
                            onSelect: onSelect,
                            onSetListeningMode: onSetListeningMode,
                            onSetSpatialAudioMode: onSetSpatialAudioMode
                        )
                    case let .nearby(accessory):
                        NearbyAccessoryRow(accessory: accessory, state: state, onConnect: onConnectNearby)
                    }
                }
            }
        }
    }
}

// Paired headphones that are advertising nearby but have no output on this Mac.
private struct NearbyAccessoryRow: View {
    let accessory: NearbyAudioAccessory
    let state: OutputAudioState
    let onConnect: (NearbyAudioAccessory) -> Void

    private var isConnecting: Bool {
        state.connectingAccessoryAddress == NearbyAudioAccessoryMatcher.canonical(accessory.address)
    }

    private var isDisabled: Bool {
        state.connectingAccessoryAddress != nil
    }

    var body: some View {
        Button {
            onConnect(accessory)
        } label: {
            HStack(spacing: 12) {
                DeviceIcon(
                    symbolName: AudioDeviceCatalog.shared.symbolName(forModelUID: accessory.modelUID) ?? "headphones",
                    systemIcon: nil,
                    isCurrent: false
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(accessory.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    // Same line metrics as DeviceBatterySummary under connected devices.
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isConnecting ? 0.5 : 1)
        .help(Text("Connect to This Mac"))
    }

    private var statusText: String {
        if isConnecting, accessory.availability == .linkedWithoutOutput {
            return String(localized: "Waiting for audio…", comment: "Status of Bluetooth headphones still linked to this Mac, such as AirPods taken out of the ears, while MacMix waits for their audio output to return.")
        }
        if isConnecting {
            return String(localized: "Connecting…", comment: "Status of nearby Bluetooth headphones while this Mac connects to them.")
        }
        switch accessory.availability {
        case .available:
            return String(localized: "Nearby, not connected", comment: "Status of paired Bluetooth headphones that are nearby but connected to no device.")
        case .linkedWithoutOutput:
            return String(localized: "Connected, not used for audio", comment: "Status of Bluetooth headphones still linked to this Mac without an audio output, such as AirPods taken out of the ears.")
        case let .inUse(byDeviceNamed: name?):
            return String(localized: "In use by \(name)", comment: "Status of nearby Bluetooth headphones connected to another device; the placeholder is that device's name.")
        case .inUse(byDeviceNamed: nil):
            return String(localized: "In use by another device", comment: "Status of nearby Bluetooth headphones connected to a device this Mac does not know.")
        }
    }
}

private struct MixSection: View {
    let audioModel: AudioModel
    @AppStorage("MacMix.MixSectionExpanded") private var isMixExpanded = true
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var enables200PercentVolume = false

    private var maximumVolume: Double {
        enables200PercentVolume ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CollapsibleHeader(title: "Mix", isExpanded: $isMixExpanded)

            if isMixExpanded {
                if audioModel.outputAppsState.needsSystemAudioPermission {
                    PermissionRequestRow(action: audioModel.requestSystemAudioPermission)
                } else if audioModel.outputAppsState.apps.isEmpty {
                    EmptyRow(iconName: "app.dashed", title: "No apps are playing audio")
                } else {
                    ForEach(audioModel.outputAppsState.apps) { app in
                        AppVolumeRow(
                            app: app,
                            maximumVolume: maximumVolume,
                            audioModel: audioModel,
                            onToggleMute: audioModel.toggleAppMute,
                            onVolumeChange: { volume, app in
                                audioModel.setAppVolume(volume, for: app)
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct InputDeviceGroup: View {
    let state: InputAudioState
    let onSelect: (AudioDevice) -> Void

    var body: some View {
        DeviceGroup(
            title: nil,
            devices: state.devices,
            batteryByDeviceUID: [:],
            accessoryControlsByDeviceUID: [:],
            reservesAccessoryControlSpace: false,
            onSelect: onSelect
        )
    }
}

private struct InputVolumeControl: View {
    let state: InputAudioState
    var showsPercentage = false
    var expandsToFill = false
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VolumeSliderRow(
            leadingIcon: state.isInputMuted ? "mic.slash.fill" : "mic.fill",
            trailingIcon: "mic.and.signal.meter.fill",
            percentage: showsPercentage ? state.inputVolume : nil,
            value: Binding(
                get: { state.inputVolume ?? 0 },
                set: onVolumeChange
            ),
            isEnabled: state.inputVolume != nil,
            isMuted: state.isInputMuted,
            expandsToFill: expandsToFill,
            onLeadingIconTap: onToggleMute
        )
    }
}

struct CollapsibleHeader: View {
    private static let expansionAnimation = Animation.smooth(duration: 0.24)

    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(Self.expansionAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceGroup: View {
    let title: LocalizedStringKey?
    let devices: [AudioDevice]
    let batteryByDeviceUID: [String: AudioDeviceBattery]
    let accessoryControlsByDeviceUID: [String: AudioAccessoryControlState]
    let reservesAccessoryControlSpace: Bool
    var accessoryControlsPresentation: AudioAccessoryControlsPresentation = .plain
    let onSelect: (AudioDevice) -> Void
    var onSetListeningMode: ((ListeningMode, AudioDevice) -> Void)? = nil
    var onSetSpatialAudioMode: ((SpatialAudioMode, AudioDevice) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            if devices.isEmpty {
                EmptyRow(iconName: "questionmark.circle", title: "No available devices")
            } else {
                ForEach(devices, id: \.selectionID) { device in
                    AudioDeviceRow(
                        device: device,
                        battery: batteryByDeviceUID[device.uid],
                        accessoryControls: accessoryControlsByDeviceUID[device.uid],
                        reservesAccessoryControlSpace: reservesAccessoryControlSpace,
                        accessoryControlsPresentation: accessoryControlsPresentation,
                        onSelect: onSelect,
                        onSetListeningMode: onSetListeningMode,
                        onSetSpatialAudioMode: onSetSpatialAudioMode
                    )
                }
            }
        }
    }
}

private enum AccessoryControlsExpansionPreference {
    static func key(for deviceUID: String) -> String {
        "MacMix.AccessoryControlsExpanded.\(deviceUID)"
    }
}

enum AudioAccessoryControlsPresentation {
    case plain
    case menuBarPanel
}

private struct AudioDeviceRow: View {
    let device: AudioDevice
    let battery: AudioDeviceBattery?
    let accessoryControls: AudioAccessoryControlState?
    let reservesAccessoryControlSpace: Bool
    var accessoryControlsPresentation: AudioAccessoryControlsPresentation = .plain
    let onSelect: (AudioDevice) -> Void
    var onSetListeningMode: ((ListeningMode, AudioDevice) -> Void)? = nil
    var onSetSpatialAudioMode: ((SpatialAudioMode, AudioDevice) -> Void)? = nil
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    @AppStorage(AccessoryDetailsVisibilityPreference.showsAccessoryDetails) private var showsAccessoryDetails = true
    @AppStorage private var isAccessoryControlsExpanded: Bool

    init(
        device: AudioDevice,
        battery: AudioDeviceBattery?,
        accessoryControls: AudioAccessoryControlState?,
        reservesAccessoryControlSpace: Bool,
        accessoryControlsPresentation: AudioAccessoryControlsPresentation = .plain,
        onSelect: @escaping (AudioDevice) -> Void,
        onSetListeningMode: ((ListeningMode, AudioDevice) -> Void)? = nil,
        onSetSpatialAudioMode: ((SpatialAudioMode, AudioDevice) -> Void)? = nil
    ) {
        self.device = device
        self.battery = battery
        self.accessoryControls = accessoryControls
        self.reservesAccessoryControlSpace = reservesAccessoryControlSpace
        self.accessoryControlsPresentation = accessoryControlsPresentation
        self.onSelect = onSelect
        self.onSetListeningMode = onSetListeningMode
        self.onSetSpatialAudioMode = onSetSpatialAudioMode
        _isAccessoryControlsExpanded = AppStorage(
            wrappedValue: false,
            AccessoryControlsExpansionPreference.key(for: device.uid)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onSelect(device)
                } label: {
                    HStack(spacing: 12) {
                        DeviceIcon(
                            symbolName: device.iconName,
                            systemIcon: device.systemIcon,
                            isCurrent: device.isCurrent
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)

                            if hasStudioAccess,
                               showsAccessoryDetails,
                               let battery,
                               battery.hasValue {
                                DeviceBatterySummary(
                                    deviceSymbolName: device.iconName,
                                    battery: battery
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let volume = device.volume {
                            Text(volume, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if hasStudioAccess,
                   showsAccessoryDetails,
                   reservesAccessoryControlSpace {
                    accessoryDisclosureButton
                        .frame(width: 18, height: 28)
                }
            }

            if hasStudioAccess,
               showsAccessoryDetails,
               isAccessoryControlsExpanded,
               let accessoryControls {
                AudioAccessoryControlsPanel(
                    state: accessoryControls,
                    presentation: accessoryControlsPresentation,
                    onSetListeningMode: { mode in
                        onSetListeningMode?(mode, device)
                    },
                    onSetSpatialAudioMode: { mode in
                        onSetSpatialAudioMode?(mode, device)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var accessoryDisclosureButton: some View {
        if accessoryControls != nil {
            Button {
                isAccessoryControlsExpanded.toggle()
            } label: {
                Image(systemName: isAccessoryControlsExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(device.name))
            .accessibilityValue(isAccessoryControlsExpanded ? Text("Expanded") : Text("Collapsed"))
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }
}

struct AudioAccessoryControlsPanel: View {
    let state: AudioAccessoryControlState
    let presentation: AudioAccessoryControlsPresentation
    let onSetListeningMode: (ListeningMode) -> Void
    let onSetSpatialAudioMode: (SpatialAudioMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !state.supportedListeningModes.isEmpty {
                ListeningModeControl(
                    supportedModes: state.supportedListeningModes,
                    selection: state.listeningMode,
                    onSelect: onSetListeningMode
                )
            }

            if !state.supportedListeningModes.isEmpty && state.supportsSpatialAudio {
                Divider()
            }

            if state.supportsSpatialAudio {
                SpatialAudioControl(
                    contentKind: state.spatialAudioContentKind,
                    selection: state.spatialAudioMode,
                    isEnabled: state.canSetSpatialAudio,
                    onSelect: onSetSpatialAudioMode
                )
            }
        }
        .padding(12)
        .background {
            if presentation == .menuBarPanel {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.5))
            }
        }
    }
}

private struct ListeningModeControl: View {
    let supportedModes: [ListeningMode]
    let selection: ListeningMode?
    let onSelect: (ListeningMode) -> Void

    private let displayOrder: [ListeningMode] = [
        .transparency,
        .adaptive,
        .noiseCancellation,
    ]

    var body: some View {
        let modes = displayOrder.filter(supportedModes.contains)

        VStack(alignment: .leading, spacing: 8) {
            Text("Listening Mode")
                .font(.subheadline.weight(.semibold))

            AccessorySegmentedControl(
                options: modes.map { AccessorySegmentOption.listeningMode($0) },
                selection: selection,
                onSelect: onSelect
            )
        }
    }
}

private struct SpatialAudioControl: View {
    let contentKind: SpatialAudioContentKind
    let selection: SpatialAudioMode?
    let isEnabled: Bool
    let onSelect: (SpatialAudioMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contentKind.localizedTitle)
                .font(.subheadline.weight(.semibold))

            AccessorySegmentedControl(
                options: SpatialAudioMode.allCases.map {
                    AccessorySegmentOption.spatialAudioMode($0)
                },
                selection: selection,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
        }
    }
}

private extension SpatialAudioContentKind {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .spatialAudio:
            "Spatial Audio"
        case .spatializeStereo:
            "Spatialize Stereo"
        }
    }
}

private struct AccessorySegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey
    let icon: AccessorySegmentIcon

    var id: Value { value }
}

private enum AccessorySegmentIcon {
    case asset(String)
}

private extension AccessorySegmentOption where Value == ListeningMode {
    static func listeningMode(_ mode: ListeningMode) -> Self {
        switch mode {
        case .transparency:
            Self(value: mode, title: "Transparency", icon: .asset("person.open.fill"))
        case .adaptive:
            Self(value: mode, title: "Adaptive", icon: .asset("person.and.sparkles.fill"))
        case .noiseCancellation:
            Self(value: mode, title: "Noise Cancellation", icon: .asset("person.closed.fill"))
        }
    }
}

private extension AccessorySegmentOption where Value == SpatialAudioMode {
    static func spatialAudioMode(_ mode: SpatialAudioMode) -> Self {
        switch mode {
        case .off:
            Self(value: mode, title: "Off", icon: .asset("person.spatialaudio.stereo.fill"))
        case .fixed:
            Self(value: mode, title: "Fixed", icon: .asset("person.spatialaudio.stereo.fill"))
        case .headTracked:
            Self(value: mode, title: "Head Tracked", icon: .asset("person.spatialaudio.stereo.3d.fill"))
        }
    }
}

private struct AccessorySegmentedControl<Value: Hashable>: View {
    let options: [AccessorySegmentOption<Value>]
    let selection: Value?
    var isEnabled = true
    let onSelect: (Value) -> Void
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @Environment(\.hasStudioAccess) private var hasStudioAccess

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.value)
                    } label: {
                        AccessorySegmentIconView(icon: option.icon)
                            .font(.body.weight(.semibold))
                            .imageScale(.medium)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(selection == option.value ? .white : .primary)
                            .background {
                                if selection == option.value {
                                    Capsule(style: .continuous)
                                        .fill(accentColor.resolvedColor(hasStudioAccess: hasStudioAccess))
                                        .padding(2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .accessibilityLabel(Text(option.title))
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .background(.quaternary.opacity(0.8), in: Capsule(style: .continuous))

            HStack(alignment: .top, spacing: 0) {
                ForEach(options) { option in
                    Text(option.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .accessibilityHidden(true)
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct AccessorySegmentIconView: View {
    let icon: AccessorySegmentIcon

    var body: some View {
        switch icon {
        case let .asset(symbolName):
            Image(symbolName)
        }
    }
}

struct DeviceBatterySummary: View {
    let deviceSymbolName: String
    let battery: AudioDeviceBattery

    var body: some View {
        let usesEarbudsPresentation = AudioDeviceSFSymbols.usesEarbudsPresentation(
            deviceSymbolName: deviceSymbolName
        )

        HStack(spacing: 10) {
            if let leftLevel = battery.left {
                BatteryMetric(
                    symbolName: AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: deviceSymbolName, side: .left),
                    level: leftLevel,
                    symbolPlacement: .leading,
                    symbolSize: .compact,
                    accessibilityLabel: "Left earbud battery"
                )
            }

            if let rightLevel = battery.right {
                BatteryMetric(
                    symbolName: AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: deviceSymbolName, side: .right),
                    level: rightLevel,
                    symbolPlacement: .leading,
                    symbolSize: .compact,
                    accessibilityLabel: "Right earbud battery"
                )
            }

            if battery.left == nil, battery.right == nil, let pairedLevel = battery.pairedLevel {
                BatteryMetric(
                    symbolName: AudioDeviceSFSymbols.pairedBatterySymbol(
                        deviceSymbolName: deviceSymbolName,
                        level: pairedLevel
                    ),
                    level: pairedLevel,
                    symbolPlacement: .leading,
                    symbolSize: .compact,
                    accessibilityLabel: usesEarbudsPresentation
                        ? "Earbuds battery"
                        : "Device battery"
                )
            }

            if battery.left == nil, battery.right == nil, let mainLevel = battery.main {
                BatteryMetric(
                    symbolName: AudioDeviceSFSymbols.batterySymbol(level: mainLevel),
                    level: mainLevel,
                    symbolPlacement: .trailing,
                    symbolSize: .regular,
                    accessibilityLabel: "Device battery"
                )
            }

            if let caseLevel = battery.caseLevel {
                BatteryMetric(
                    symbolName: AudioDeviceSFSymbols.caseBatterySymbol(
                        deviceSymbolName: deviceSymbolName,
                        level: caseLevel
                    ),
                    level: caseLevel,
                    symbolPlacement: .leading,
                    symbolSize: .compact,
                    accessibilityLabel: "Charging case battery"
                )
            }
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

private enum BatteryMetricSymbolPlacement {
    case leading
    case trailing
}

private enum BatteryMetricSymbolSize {
    case compact
    case regular

    var font: Font {
        switch self {
        case .compact:
            .subheadline
        case .regular:
            .body
        }
    }
}

private struct BatteryMetric: View {
    let symbolName: String
    let level: Int
    let symbolPlacement: BatteryMetricSymbolPlacement
    let symbolSize: BatteryMetricSymbolSize
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        HStack(spacing: 3) {
            if symbolPlacement == .leading {
                BatteryMetricIcon(symbolName: symbolName, size: symbolSize)
            }

            Text(Double(level) / 100, format: .percent.precision(.fractionLength(0)))

            if symbolPlacement == .trailing {
                BatteryMetricIcon(symbolName: symbolName, size: symbolSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(
            Text(Double(level) / 100, format: .percent.precision(.fractionLength(0)))
        )
    }
}

private struct BatteryMetricIcon: View {
    let symbolName: String
    let size: BatteryMetricSymbolSize

    var body: some View {
        Image(systemName: symbolName)
            .font(size.font)
            .imageScale(.medium)
    }
}

struct AppVolumeRow: View {
    let app: AudioAppState
    let maximumVolume: Double
    var audioModel: AudioModel? = nil
    var layout: AppVolumeRowLayout = .compact
    let onToggleMute: (AudioAppState) -> Void
    let onVolumeChange: (Double, AudioAppState) -> Void

    var body: some View {
        if let audioModel {
            AppEqualizerRow(app: app, audioModel: audioModel, maximumVolume: maximumVolume, layout: layout,
                onToggleMute: { onToggleMute(app) }, onVolumeChange: { onVolumeChange($0, app) })
        } else { controls }
    }
    private var controls: some View {
        AppVolumeControls(name: app.name, icon: app.icon, volume: app.volume, isMuted: app.isMuted,
                          maximumVolume: maximumVolume, layout: layout,
                          onToggleMute: { onToggleMute(app) },
                          onVolumeChange: { onVolumeChange($0, app) })
    }
}

struct AppVolumeControls: View {
    let name: String
    let icon: NSImage?
    let volume: Double
    let isMuted: Bool
    let maximumVolume: Double
    var layout: AppVolumeRowLayout = .compact
    var audioControlsExpanded: Binding<Bool>? = nil
    let onToggleMute: () -> Void
    let onVolumeChange: (Double) -> Void
    @State private var isAtUnity = false
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @Environment(\.hasStudioAccess) private var hasStudioAccess

    private var sliderTint: Color {
        if isMuted {
            return MacMixTint.gray
        }

        return volume > 1
            ? MacMixTint.yellow
            : accentColor.resolvedColor(hasStudioAccess: hasStudioAccess)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggleMute()
            } label: {
                AppIcon(image: icon, isMuted: isMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
            .accessibilityLabel(isMuted ? Text("Unmute") : Text("Mute"))

            Text(name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .frame(
                    minWidth: layout == .controlPanel ? 90 : 60,
                    idealWidth: layout == .controlPanel ? 110 : 60,
                    maxWidth: layout == .controlPanel ? 130 : 60,
                    alignment: .leading
                )

            AppMixVolumeSlider(value: volumeBinding, maximumVolume: maximumVolume,
                               layout: layout, tint: sliderTint)

            MixVolumeRestoreControl(value: volume) {
                updateVolume(1)
            }
            if let audioControlsExpanded {
                Button { audioControlsExpanded.wrappedValue.toggle() } label: {
                    Image(systemName: audioControlsExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Audio Controls", tableName: "AppOutputRouting"))
                .accessibilityValue(audioControlsExpanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
            }
        }
        .padding(.vertical, 2)
        .frame(
            minWidth: layout == .controlPanel ? 0 : nil,
            maxWidth: layout == .controlPanel ? .infinity : nil
        )
        // Touch and hold reaches the row's small or hover-only controls.
        .contextMenu {
            Button(action: onToggleMute) {
                Label {
                    isMuted ? Text("Unmute") : Text("Mute")
                } icon: {
                    Image(systemName: isMuted ? "speaker.wave.2" : "speaker.slash")
                }
            }
            Button {
                updateVolume(1)
            } label: {
                Label(MixVolumeRestoreControl.restoreTitle, systemImage: "arrow.clockwise")
            }
            .disabled(abs(volume - 1) < 0.005)
            if let audioControlsExpanded {
                Toggle(isOn: audioControlsExpanded) {
                    Text("Audio Controls", tableName: "AppOutputRouting")
                }
            }
        }
        .sensoryFeedback(.alignment, trigger: isAtUnity) { _, isAtUnity in
            isAtUnity
        }
    }

    private func updateVolume(_ volume: Double) {
        isAtUnity = abs(volume - 1) < 0.005
        onVolumeChange(volume)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { min(volume, maximumVolume) },
            set: { updateVolume($0) }
        )
    }

}

struct AppMixVolumeSlider: View {
    @Binding var value: Double
    let maximumVolume: Double
    var layout: AppVolumeRowLayout = .controlPanel
    var tint: Color = .accentColor

    var body: some View {
        Group {
            if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass, maximumVolume > 1 {
                if layout == .controlPanel {
                    boostedSlider.labelsHidden()
                } else {
                    boostedSlider
                }
            } else {
                Slider(value: $value, in: 0...maximumVolume)
                    .labelsHidden()
                    .tint(tint)
            }
        }
        .frame(minWidth: layout == .controlPanel ? ControlPanelLayout.mixSliderMinimumWidth : nil)
    }

    @available(macOS 26.0, *)
    private var boostedSlider: some View {
        Slider(value: $value, in: 0...maximumVolume, label: { EmptyView() }, ticks: { SliderTick(1) })
            .tint(tint)
    }
}

enum AppVolumeRowLayout {
    case compact
    case controlPanel
}

struct MixVolumeRestoreControl: View {
    let value: Double
    let onRestore: () -> Void
    @State private var isHovering = false
    @State private var isRevealedByTap = false

    private var showsRestore: Bool { isHovering || isRevealedByTap }

    var body: some View {
        Button(action: activate) {
            ZStack {
                PercentageText(value: value)
                    .opacity(showsRestore ? 0 : 1)

                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .opacity(showsRestore ? 1 : 0)
            }
            .frame(width: 34, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .task(id: isRevealedByTap) {
            guard isRevealedByTap, (try? await Task.sleep(for: .seconds(3))) != nil else { return }
            isRevealedByTap = false
        }
        .help(Self.restoreTitle)
        .accessibilityLabel(Text(Self.restoreTitle))
    }

    /// A pointer always hovers before it clicks. A click without hover comes
    /// from touch, which only reveals the hidden glyph; the next tap restores.
    private func activate() {
        let type = NSApp.currentEvent?.type
        if !showsRestore, type == .leftMouseUp || type == .leftMouseDown {
            isRevealedByTap = true
            return
        }
        isRevealedByTap = false
        onRestore()
    }

    static var restoreTitle: String {
        String(
            localized: "Restore to \(1.0, format: .percent.precision(.fractionLength(0)))",
            comment: "Tooltip and accessibility label for the per-app mix volume restore button."
        )
    }
}

private struct VolumeSliderRow: View {
    let leadingIcon: String
    let trailingIcon: String
    var percentage: Double? = nil
    @Binding var value: Double
    var isEnabled = true
    var isMuted = false
    var expandsToFill = false
    var maximumVolume: Double = 1
    var onLeadingIconTap: (() -> Void)?
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @Environment(\.hasStudioAccess) private var hasStudioAccess

    var body: some View {
        HStack(spacing: 10) {
            if let onLeadingIconTap {
                Button(action: onLeadingIconTap) {
                    DrawSwapSymbol(name: leadingIcon) { SliderSymbol(name: $0, isMuted: isMuted) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
                .accessibilityLabel(isMuted ? Text("Unmute") : Text("Mute"))
            } else {
                SliderSymbol(name: leadingIcon)
            }

            Slider(value: $value, in: 0...maximumVolume)
                .tint(
                    isMuted
                        ? MacMixTint.gray
                        : accentColor.resolvedColor(hasStudioAccess: hasStudioAccess)
                )
                .disabled(!isEnabled)

            SliderSymbol(name: trailingIcon)

            if let percentage {
                PercentageText(value: percentage)
            }
        }
        .frame(maxWidth: expandsToFill ? .infinity : nil)
        .frame(height: 28)
    }
}

private struct PercentageText: View {
    let value: Double

    var body: some View {
        Text(value.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .center)
    }
}

private struct SliderSymbol: View {
    let name: String
    var isMuted = false

    var body: some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(isMuted ? .red : .secondary)
            .frame(width: 24, height: 24, alignment: .center)
    }
}

/// Swaps symbols by drawing the old one off and the new one on; systems
/// before macOS 26 fall back to the replace effect.
private struct DrawSwapSymbol<Content: View>: View {
    let name: String
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    content(name)
                        .id(name)
                        .transition(AsymmetricTransition(
                            insertion: .symbolEffect(.drawOn),
                            removal: .symbolEffect(.drawOff)
                        ))
                }
            } else {
                content(name)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .animation(.default, value: name)
    }
}

struct DeviceIcon: View {
    let symbolName: String
    let systemIcon: NSImage?
    let isCurrent: Bool
    var showsBackground = true
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @Environment(\.hasStudioAccess) private var hasStudioAccess

    var body: some View {
        ZStack {
            if showsBackground {
                Circle()
                    .fill(
                        isCurrent
                            ? accentColor.resolvedColor(hasStudioAccess: hasStudioAccess)
                            : Color.secondary.opacity(0.16)
                    )
            }

            if let systemIcon {
                Image(nsImage: systemIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: AudioDeviceSFSymbols.deviceSymbol(preferredName: symbolName))
                    .font(.body.weight(.semibold))
                    .imageScale(.medium)
                    .foregroundStyle(isCurrent && showsBackground ? .white : .secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(width: 26, height: 26)
    }
}

struct AppIcon: View {
    let image: NSImage?
    let isMuted: Bool

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .scaledToFit()
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .saturation(isMuted ? 0 : 1)
            .opacity(isMuted ? 0.3 : 1)

            muteBadge
        }
        .frame(width: 24, height: 24)
        .animation(.default, value: isMuted)
    }

    @ViewBuilder
    private var muteBadge: some View {
        let badge = Image(systemName: "speaker.slash.fill")
            .font(.caption.weight(.bold))
            .imageScale(.medium)
            .foregroundStyle(.red)
        if #available(macOS 26.0, *) {
            if isMuted {
                badge.transition(AsymmetricTransition(
                    insertion: .symbolEffect(.drawOn),
                    removal: .symbolEffect(.drawOff)
                ))
            }
        } else {
            badge.opacity(isMuted ? 1 : 0)
        }
    }
}

struct EmptyRow: View {
    let iconName: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.12), in: Circle())

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct PermissionRequestRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.12), in: Circle())

                Text("System audio recording permission required")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MacMixPanel(
        audioModel: AudioModel(),
        nowPlayingModel: NowPlayingModel(startsListening: false),
        hasStudioAccess: true
    )
}

