import MacMixStudio
import SwiftUI

struct MixVolumeShortcutPicker: View {
    @Bindable var model: SystemVolumeTakeoverModel
    @State private var showsRequirement = false

    var body: some View {
        LabeledContent("Mix Global Shortcuts") {
            Picker("Mix Global Shortcuts", selection: $model.mixShortcutModifier) {
                ForEach(MixVolumeShortcutModifier.allCases) { modifier in
                    if modifier == .disabled {
                        Text("Off").tag(modifier)
                    } else {
                        Text(verbatim: modifier.symbol + " 1–9 F10/F11/F12").tag(modifier)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!model.isEnabled)
            .overlay {
                if !model.isEnabled {
                    Button { showsRequirement = true } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mix Global Shortcuts")
                    .accessibilityHint("This feature requires Take Over System Volume Controls.")
                }
            }
            .popover(isPresented: $showsRequirement, arrowEdge: .bottom) {
                Text("This feature requires Take Over System Volume Controls.")
                    .multilineTextAlignment(.center)
                    .frame(width: 240, alignment: .center)
                    .padding()
            }
        }
        .onChange(of: model.isEnabled) { showsRequirement = false }
    }
}
