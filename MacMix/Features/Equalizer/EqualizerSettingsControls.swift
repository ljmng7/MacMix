import SwiftUI
import MacMixStudio

struct CustomEqualizerSettingsToggle: View {
    let audioModel: AudioModel
    @State private var showsVolumeNotice = false
    var body: some View {
        Toggle("Custom EQ", isOn: Binding(
            get: { audioModel.equalizerStore.isEnabled },
            set: { enabled in
                audioModel.setCustomEqualizerEnabled(enabled)
                if enabled && audioModel.equalizerStore.isFeatureActive { showsVolumeNotice = true }
            }
        ))
        .toggleStyle(.switch)
        .alert("EQ Volume Limit", isPresented: $showsVolumeNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Custom EQ turns off \(2.0, format: .percent.precision(.fractionLength(0))) volume. Turning off Custom EQ restores it automatically.")
        }
    }
}

struct MultiOutputSettingsToggle: View {
    let audioModel: AudioModel
    var body: some View {
        Toggle(isOn: Binding(
            get: { audioModel.outputRoutingStore.isEnabled },
            set: { audioModel.setMultiOutputEnabled($0) }
        )) {
            Text("Multi-Device Output", tableName: "AppOutputRouting")
        }
        .toggleStyle(.switch)
    }
}

struct EqualizerAwareBoostToggle: View {
    @Binding var isOn: Bool
    let isBlocked: Bool
    @State private var showsReason = false
    var body: some View {
        HStack {
            Text("Enable \(2.0, format: .percent.precision(.fractionLength(0))) Volume",
                 comment: "Settings toggle that lets per-app mix volume sliders boost above 100 percent.")
            Spacer()
            Toggle(isOn: Binding(get: { isBlocked ? false : isOn }, set: { value in
                if isBlocked { showsReason = true } else { isOn = value }
            })) {
                Text("Enable \(2.0, format: .percent.precision(.fractionLength(0))) Volume",
                     comment: "Settings toggle that lets per-app mix volume sliders boost above 100 percent.")
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .disabled(isBlocked)
            .accessibilityHidden(isBlocked)
            .overlay {
                if isBlocked {
                    Button { showsReason = true } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unavailable while Custom EQ is enabled")
                }
            }
            .popover(isPresented: $showsReason, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                Text("Unavailable while Custom EQ is enabled")
                    .padding(12)
                    .fixedSize()
            }
        }
    }
}
