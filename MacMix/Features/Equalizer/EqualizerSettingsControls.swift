import SwiftUI
import MacMixStudio

struct CustomEqualizerSettingsToggle: View {
    let audioModel: AudioModel
    var body: some View {
        Toggle("Custom EQ", isOn: Binding(
            get: { audioModel.equalizerStore.isEnabled },
            set: { audioModel.setCustomEqualizerEnabled($0) }
        ))
        .toggleStyle(.switch)
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
