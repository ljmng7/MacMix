import SwiftUI
import CoreAudio
import MacMixStudio

struct AppAudioSectionHeader: View {
    let title: Text
    /// `nil` shows a plain title for a section that cannot collapse.
    let isExpanded: Binding<Bool>?

    var body: some View {
        if let isExpanded {
            collapsibleHeader(isExpanded)
        } else {
            title.font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        }
    }

    private func collapsibleHeader(_ isExpanded: Binding<Bool>) -> some View {
        Button { isExpanded.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                title.font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }
}

struct AppOutputRoutingPicker: View {
    let app: AudioAppState
    let audioModel: AudioModel
    var layout: AppVolumeRowLayout = .compact
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    private var store: AppOutputRoutingStore { audioModel.outputRoutingStore }
    private var selected: [AppOutputDestination] { store.destinations(for: app.bundleID) }
    private var available: [AppOutputDestination] { audioModel.outputState.routingDestinations }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { audioModel.followSystemOutput(for: app) } label: {
                HStack(spacing: 12) {
                    DeviceIcon(symbolName: audioModel.outputState.menuBarSymbolName,
                               systemIcon: nil, isCurrent: selected.isEmpty)
                    Text("Follow system output", tableName: "AppOutputRouting")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if layout == .compact { Divider() }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(audioModel.outputState.routingDevices) { device in
                    RoutedOutputDeviceRow(device: device, volumeState: audioModel.routedDeviceVolumeState(for: device),
                        audioModel: audioModel, layout: layout,
                        isSelected: selected.contains { $0.matches(destination(for: device)) }, hasAccess: hasStudioAccess,
                        onSelection: { audioModel.setOutputDestination(destination(for: device), selected: $0, for: app) })
                }
                ForEach(selected.filter { saved in !available.contains { saved.matches($0) } }) { device in
                    offlineDestinationRow(device)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if audioModel.outputState.devices.contains(where: { $0.transportType == kAudioDeviceTransportTypeAirPlay }) {
                Text("AirPlay uses the receivers connected in the system output selector.", tableName: "AppOutputRouting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.applyFailed {
                Button { audioModel.retryAppOutputRouting() } label: {
                    Text("Retry", tableName: "AppOutputRouting")
                }
            }
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func destination(for device: AudioDevice) -> AppOutputDestination {
        AppOutputDestination(uid: device.uid, name: device.name, dataSourceIDs: device.selectedDataSourceIDs)
    }

    private func offlineDestinationRow(_ device: AppOutputDestination) -> some View {
        HStack(spacing: 8) {
            Button {
                audioModel.setOutputDestination(device,
                    selected: !selected.contains { $0.id == device.id }, for: app)
            } label: {
                HStack(spacing: 12) {
                    DeviceIcon(symbolName: "speaker.slash", systemIcon: nil, isCurrent: true)
                    SceneFadingName(name: device.name, maximumWidth: layout == .compact ? 72 : 150)
                        .font(.body.weight(.medium))
                        .frame(width: layout == .compact ? 72 : 150, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasStudioAccess)
            .accessibilityLabel(Text(device.name))
            .accessibilityAddTraits(.isSelected)
            AppMixVolumeSlider(value: .constant(0), maximumVolume: 1, layout: layout)
                .disabled(true)
                .accessibilityLabel(Text(device.name))
                .accessibilityValue(Text("Offline", tableName: "AppOutputRouting"))
            Text(verbatim: "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .help(String(localized: "Offline", table: "AppOutputRouting"))
    }
}

private struct RoutedOutputDeviceRow: View {
    let device: AudioDevice
    let volumeState: RoutedDeviceVolumeState
    let audioModel: AudioModel
    let layout: AppVolumeRowLayout
    let isSelected: Bool
    let hasAccess: Bool
    let onSelection: (Bool) -> Void
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system

    private var volume: Double? {
        audioModel.currentOutputDevice?.uid == device.uid
            ? audioModel.outputState.systemVolume : volumeState.volume
    }
    private var canAdjust: Bool { hasAccess && isSelected && volume != nil }

    var body: some View {
        HStack(spacing: 8) {
            Button { onSelection(!isSelected) } label: {
                HStack(spacing: 12) {
                    DeviceIcon(symbolName: device.iconName, systemIcon: device.systemIcon, isCurrent: isSelected)
                    SceneFadingName(name: device.name, maximumWidth: layout == .compact ? 72 : 150)
                        .font(.body.weight(.medium))
                        .frame(width: layout == .compact ? 72 : 150, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasAccess)
            .help(device.name)
            .accessibilityLabel(Text(device.name))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            AppMixVolumeSlider(value: Binding(get: { volume ?? 0 }, set: { value in
                guard canAdjust else { return }
                audioModel.setRoutedDeviceVolume(value, device: device)
            }), maximumVolume: 1, layout: layout,
               tint: accentColor.resolvedColor(hasStudioAccess: hasAccess))
                .disabled(!canAdjust)
                .accessibilityLabel(Text(device.name))
            MixVolumeRestoreControl(value: volume ?? 0) {
                guard canAdjust else { return }
                audioModel.setRoutedDeviceVolume(1, device: device)
            }
            .disabled(!canAdjust)
        }
        .frame(minHeight: 28)
    }
}

