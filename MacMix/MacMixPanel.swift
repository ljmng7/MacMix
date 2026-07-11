//
//  MacMixPanel.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

struct MacMixPanel: View {
    let audioModel: AudioModel
    @AppStorage(PanelVisibilityPreference.showsOutput) private var showsOutputInPanel = true
    @AppStorage(PanelVisibilityPreference.showsInput) private var showsInputInPanel = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            SystemVolumeSection(audioModel: audioModel)

            Divider()

            if showsOutputInPanel {
                OutputSection(audioModel: audioModel)
            }

            if showsOutputInPanel && showsInputInPanel {
                Divider()
            }

            if showsInputInPanel {
                InputSection(audioModel: audioModel)
            }

            if showsOutputInPanel || showsInputInPanel {
                Divider()
            }

            Button {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "control-panel")
                NSApp.activate(ignoringOtherApps: true)
                dismiss()
            } label: {
                Label("Open Main Window", systemImage: "macwindow")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical, 4)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit MacMix", systemImage: "power")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private enum PanelVisibilityPreference {
    static let showsOutput = "MacMix.ShowsOutputInPanel"
    static let showsInput = "MacMix.ShowsInputInPanel"
}

struct MacMixControlPanel: View {
    let audioModel: AudioModel
    @Binding var selection: ControlPanelPage
    let updater: SPUUpdater
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ControlPanelSidebar(selection: $selection)
        } detail: {
            ControlPanelDetail(selection: selection, audioModel: audioModel, updater: updater)
        }
    }
}

enum ControlPanelLayout {
    static let sidebarMinWidth: CGFloat = 150
    static let sidebarIdealWidth: CGFloat = sidebarMinWidth
    static let sidebarMaxWidth: CGFloat = 280
    static let detailMinWidth: CGFloat = 520
    static let detailIdealWidth: CGFloat = detailMinWidth
    static let defaultWindowWidth: CGFloat = sidebarIdealWidth + detailIdealWidth
}

private struct ControlPanelSidebar: View {
    @Binding var selection: ControlPanelPage

    var body: some View {
        List(selection: $selection) {
            Label("Settings", systemImage: "slider.horizontal.3")
                .tag(ControlPanelPage.settings)

            Label("About", systemImage: "info.circle")
                .tag(ControlPanelPage.about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: ControlPanelLayout.sidebarMinWidth,
                ideal: ControlPanelLayout.sidebarIdealWidth,
                max: ControlPanelLayout.sidebarMaxWidth
            )
    }
}

private struct ControlPanelDetail: View {
    let selection: ControlPanelPage
    let audioModel: AudioModel
    let updater: SPUUpdater

    var body: some View {
        Group {
            switch selection {
            case .settings:
                ControlPanelSettingsPage(audioModel: audioModel, updater: updater)
            case .about:
                ControlPanelAboutPage(audioModel: audioModel, updater: updater)
            }
        }
        .navigationSplitViewColumnWidth(
            min: ControlPanelLayout.detailMinWidth,
            ideal: ControlPanelLayout.detailIdealWidth
        )
    }
}

enum ControlPanelPage: Hashable {
    case settings
    case about
}

private struct ControlPanelSettingsPage: View {
    let audioModel: AudioModel
    let updater: SPUUpdater
    @AppStorage(PanelVisibilityPreference.showsOutput) private var showsOutputInPanel = true
    @AppStorage(PanelVisibilityPreference.showsInput) private var showsInputInPanel = true
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var enables200PercentVolume = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SystemVolumeSection(audioModel: audioModel)

                Divider()

                PanelVisibilityHeader(
                    title: "Output",
                    accessibilityLabel: "Show output in panel",
                    isVisible: $showsOutputInPanel
                )

                if showsOutputInPanel {
                    OutputDeviceGroup(
                        state: audioModel.outputState,
                        onSelect: audioModel.selectOutputDevice
                    )

                    MixSection(
                        state: audioModel.outputAppsState,
                        boostPreference: $enables200PercentVolume,
                        onRequestPermission: audioModel.requestSystemAudioPermission,
                        onVolumeChange: { volume, app in
                            audioModel.setAppVolume(volume, for: app)
                        }
                    )
                }

                Divider()

                PanelVisibilityHeader(
                    title: "Input",
                    accessibilityLabel: "Show input in panel",
                    isVisible: $showsInputInPanel
                )

                if showsInputInPanel {
                    InputDeviceGroup(
                        state: audioModel.inputState,
                        onSelect: audioModel.selectInputDevice
                    )

                    InputVolumeControl(
                        state: audioModel.inputState,
                        onVolumeChange: audioModel.setInputVolume
                    )
                }

                Divider()

                HStack(spacing: 28) {
                    OpenAtLoginToggle()

                    AutomaticUpdatesToggle(updater: updater)
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(minWidth: ControlPanelLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
        .onChange(of: enables200PercentVolume) { _, isEnabled in
            if !isEnabled {
                audioModel.clampAppVolumesToUnity()
            }
        }
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
    let updater: SPUUpdater
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 10) {
                    Image(colorScheme == .dark ? "AboutAppIconDark" : "AboutAppIconDefault")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .compositingGroup()
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.22), radius: 18, x: 0, y: 10)
                        .accessibilityHidden(true)

                    Text(verbatim: "MacMix")
                        .font(.system(size: 28, weight: .semibold))

                    Text(Self.versionText)
                        .font(.system(size: 13, weight: .medium))

                    Text(verbatim: "Ⓒ2026 Jazmín")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)

                AboutCheckForUpdatesButton(updater: updater)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy Information")
                        .font(.headline.weight(.semibold))

                    PermissionAccessRow(
                        state: audioModel.outputAppsState,
                        action: audioModel.openSystemAudioRecordingSettingsForAuthorization
                    )

                    Text("Mixing needs System Audio Recording permission because macOS requires this permission before an app can process another app's audio. MacMix uses it only for local real-time mixing when you adjust per-app volume, and does not record, save, or upload audio.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StarOnGitHubLink()
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: ControlPanelLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("About")
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return String(
                format: String(
                    localized: "Version %1$@(%2$@)",
                    comment: "About page version label with marketing version and build number."
                ),
                version,
                build
            )
        case let (.some(version), .none):
            return String(
                format: String(
                    localized: "Version %@",
                    comment: "About page version label with only the marketing version."
                ),
                version
            )
        case let (.none, .some(build)):
            return String(
                format: String(
                    localized: "Build %@",
                    comment: "About page build label shown when the marketing version is unavailable."
                ),
                build
            )
        case (.none, .none):
            return String(
                localized: "Version Unknown",
                comment: "About page fallback when app version metadata is unavailable."
            )
        }
    }
}

private struct AboutCheckForUpdatesButton: View {
    let updater: SPUUpdater

    var body: some View {
        if #available(macOS 26.0, *) {
            HStack {
                Spacer(minLength: 0)

                checkForUpdatesButton
                    .buttonStyle(.plain)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .glassEffect(.regular.interactive())

                Spacer(minLength: 0)
            }
        } else {
            HStack {
                Spacer(minLength: 0)

                checkForUpdatesButton
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .controlSize(.large)

                Spacer(minLength: 0)
            }
        }
    }

    private var checkForUpdatesButton: some View {
        CheckForUpdatesView(updater: updater, showsIcon: true, showsEllipsis: false)
    }
}

private struct StarOnGitHubLink: View {
    private let repositoryURL = URL(string: "https://github.com/ljmng7/MacMix")!

    var body: some View {
        Link(destination: repositoryURL) {
            HStack(spacing: 8) {
                Text("Star me on GitHub🤗")
                    .font(.system(size: 14, weight: .semibold))

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
        .padding(.top, 8)
    }
}

private struct PermissionAccessRow: View {
    @ObservedObject var state: OutputAppsState
    let action: () -> Void

    private var isAuthorized: Bool {
        state.isSystemAudioPermissionAuthorized
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("System Audio Recording")
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 16)

            if isAuthorized {
                Text("Authorized")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text("Go to Authorize")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .font(.system(size: 13, weight: .medium))
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

private struct SystemVolumeSection: View {
    let audioModel: AudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Volume")
                .font(.headline.weight(.semibold))

            SystemVolumeControl(
                state: audioModel.outputState,
                onVolumeChange: audioModel.setSystemOutputVolume
            )
        }
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
                    onSelect: audioModel.selectOutputDevice
                )

                MixSection(
                    state: audioModel.outputAppsState,
                    onRequestPermission: audioModel.requestSystemAudioPermission,
                    onVolumeChange: { volume, app in
                        audioModel.setAppVolume(volume, for: app)
                    }
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
                    onVolumeChange: audioModel.setInputVolume
                )
            }
        }
    }
}

private struct SystemVolumeControl: View {
    @ObservedObject var state: OutputAudioState
    let onVolumeChange: (Double) -> Void

    var body: some View {
        VolumeSliderRow(
            leadingIcon: (state.systemVolume ?? 1) <= 0.001 ? "speaker.slash.fill" : "speaker.fill",
            trailingIcon: "speaker.wave.3.fill",
            percentage: state.systemVolume,
            value: Binding(
                get: { state.systemVolume ?? 0 },
                set: onVolumeChange
            ),
            isEnabled: state.systemVolume != nil
        )
    }
}

private struct OutputDeviceGroup: View {
    @ObservedObject var state: OutputAudioState
    let onSelect: (AudioDevice) -> Void

    var body: some View {
        DeviceGroup(
            title: nil,
            devices: state.devices,
            onSelect: onSelect
        )
    }
}

private struct MixSection: View {
    @ObservedObject var state: OutputAppsState
    var boostPreference: Binding<Bool>? = nil
    let onRequestPermission: () -> Void
    let onVolumeChange: (Double, AudioApp) -> Void
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var enables200PercentVolume = false

    private var maximumVolume: Double {
        enables200PercentVolume ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mix")
                    .font(.headline.weight(.semibold))

                Spacer()

                if let boostPreference {
                    Toggle(isOn: boostPreference) {
                        Text(
                            "Enable \(2.0, format: .percent.precision(.fractionLength(0))) Volume",
                            comment: "Settings toggle that lets per-app mix volume sliders boost above 100 percent."
                        )
                    }
                    .toggleStyle(.switch)
                }
            }

            if state.needsSystemAudioPermission {
                PermissionRequestRow(action: onRequestPermission)
            } else if state.apps.isEmpty {
                EmptyRow(iconName: "app.dashed", title: "No apps are playing audio")
            } else {
                ForEach(state.apps) { app in
                    AppVolumeRow(
                        app: app,
                        maximumVolume: maximumVolume,
                        onVolumeChange: onVolumeChange
                    )
                }
            }
        }
    }
}

private struct InputDeviceGroup: View {
    @ObservedObject var state: InputAudioState
    let onSelect: (AudioDevice) -> Void

    var body: some View {
        DeviceGroup(
            title: nil,
            devices: state.devices,
            onSelect: onSelect
        )
    }
}

private struct InputVolumeControl: View {
    @ObservedObject var state: InputAudioState
    let onVolumeChange: (Double) -> Void

    var body: some View {
        VolumeSliderRow(
            leadingIcon: "mic.fill",
            trailingIcon: "mic.and.signal.meter.fill",
            value: Binding(
                get: { state.inputVolume ?? 0 },
                set: onVolumeChange
            ),
            isEnabled: state.inputVolume != nil
        )
    }
}

private struct CollapsibleHeader: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceGroup: View {
    let title: LocalizedStringKey?
    let devices: [AudioDevice]
    let onSelect: (AudioDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            if devices.isEmpty {
                EmptyRow(iconName: "questionmark.circle", title: "No available devices")
            } else {
                ForEach(devices) { device in
                    Button {
                        onSelect(device)
                    } label: {
                        HStack(spacing: 12) {
                            DeviceIcon(device: device)

                            Text(device.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let volume = device.volume {
                                Text(volume.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp
    let maximumVolume: Double
    let onVolumeChange: (Double, AudioApp) -> Void
    @State private var isAtUnity = false

    private var sliderTint: Color {
        app.volume > 1 ? .yellow : .blue
    }

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(image: app.icon)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)

            VStack(spacing: 2) {
                if #available(macOS 26.0, *), maximumVolume > 1 {
                    Slider(
                        value: volumeBinding,
                        in: 0...maximumVolume,
                        label: {
                            EmptyView()
                        },
                        ticks: {
                            SliderTick(1)
                        }
                    )
                    .tint(sliderTint)
                } else {
                    Slider(value: volumeBinding, in: 0...maximumVolume)
                    .tint(sliderTint)
                }
            }

            MixVolumeRestoreControl(value: app.volume) {
                updateVolume(1)
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.alignment, trigger: isAtUnity) { _, isAtUnity in
            isAtUnity
        }
    }

    private func updateVolume(_ volume: Double) {
        isAtUnity = abs(volume - 1) < 0.005
        onVolumeChange(volume, app)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { min(app.volume, maximumVolume) },
            set: { updateVolume($0) }
        )
    }
}

private struct MixVolumeRestoreControl: View {
    let value: Double
    let onRestore: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onRestore) {
            ZStack {
                PercentageText(value: value)
                    .opacity(isHovering ? 0 : 1)

                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .frame(width: 34, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(restoreTitle)
        .accessibilityLabel(Text(restoreTitle))
    }

    private var restoreTitle: String {
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

    var body: some View {
        HStack(spacing: 10) {
            SliderSymbol(name: leadingIcon)

            Slider(value: $value, in: 0...1)
                .tint(.blue)
                .disabled(!isEnabled)

            SliderSymbol(name: trailingIcon)

            if let percentage {
                PercentageText(value: percentage)
            }
        }
        .frame(height: 28)
    }
}

private struct PercentageText: View {
    let value: Double

    var body: some View {
        Text(value.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
    }
}

private struct SliderSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24, alignment: .center)
    }
}

private struct DeviceIcon: View {
    let device: AudioDevice

    var body: some View {
        ZStack {
            Circle()
                .fill(device.isCurrent ? Color.blue : Color.secondary.opacity(0.16))

            Image(systemName: device.iconName)
                .font(.system(size: 13, weight: .semibold))
                .imageScale(.medium)
                .foregroundStyle(device.isCurrent ? .white : .secondary)
                .frame(width: 24, height: 24)
        }
        .frame(width: 26, height: 26)
    }
}

private struct AppIcon: View {
    let image: NSImage?

    var body: some View {
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
    }
}

private struct EmptyRow: View {
    let iconName: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.12), in: Circle())

            Text(title)
                .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.12), in: Circle())

                Text("System audio recording permission required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MacMixPanel(audioModel: AudioModel())
}
