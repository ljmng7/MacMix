import SwiftUI

enum SceneAppearance {
    struct Swatch: Identifiable {
        let id: String
        let color: Color
    }
    static let colors: [Swatch] = [
        .init(id: "red", color: .red), .init(id: "orange", color: .orange),
        .init(id: "yellow", color: .yellow), .init(id: "green", color: .green),
        .init(id: "mint", color: .mint), .init(id: "teal", color: .teal),
        .init(id: "cyan", color: .cyan), .init(id: "blue", color: .blue),
        .init(id: "indigo", color: .indigo), .init(id: "purple", color: .purple),
        .init(id: "pink", color: .pink), .init(id: "brown", color: .brown),
        .init(id: "gray", color: .gray), .init(id: "sage", color: Color(red: 0.55, green: 0.67, blue: 0.58)),
        .init(id: "coral", color: Color(red: 1, green: 0.5, blue: 0.4)),
        .init(id: "navy", color: Color(red: 0.18, green: 0.27, blue: 0.48))
    ]
    static let symbols = AudioSceneAppearance.symbols
    static func color(_ id: String) -> Color { colors.first { $0.id == id }?.color ?? .purple }
}

struct SceneAppearanceEditor: View {
    @Binding var scene: AudioScenePreset
    var nameDraft: Binding<String>? = nil
    var defaultName: String
    var actionColor: Color = .accentColor
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var reservesActionsSpace = false
    @State private var search = ""
    @State private var nameHasUncommittedText = false

    private var symbols: [SceneSymbolGroup.Symbol] {
        SceneSymbolGroup.matching(search)
    }

    var body: some View {
        let name = nameDraft ?? $scene.name
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack(alignment: .leading) {
                        if name.wrappedValue.isEmpty && !nameHasUncommittedText {
                            Text(verbatim: defaultName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        SceneNameEditor(text: name) { nameHasUncommittedText = $0 }
                    }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(height: 40)
                        .modifier(SceneNameSurface())
                        .accessibilityLabel("Scene Name")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(SceneAppearance.colors) { swatch in
                            Button { scene.color = swatch.id } label: {
                                Circle().fill(swatch.color.gradient).frame(width: 26, height: 26)
                                    .overlay {
                                        if scene.color == swatch.id {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                                .shadow(color: .black.opacity(0.5), radius: 1)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(LocalizedStringKey("Scene color " + swatch.id)))
                            .accessibilityAddTraits(scene.color == swatch.id ? .isSelected : [])
                        }
                    }
                    SceneSymbolSearchField(text: $search).frame(height: 34)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 6) {
                        ForEach(symbols) { symbol in
                            Button { scene.symbol = symbol.id } label: {
                                Image(systemName: symbol.id).font(.title2).frame(width: 39, height: 39)
                                    .foregroundStyle(scene.symbol == symbol.id ? SceneAppearance.color(scene.color) : .secondary)
                                    .background { SceneSymbolSelectionSurface(isSelected: scene.symbol == symbol.id) }
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(symbol.label))
                            .accessibilityAddTraits(scene.symbol == symbol.id ? .isSelected : [])
                        }
                    }
                    if symbols.isEmpty {
                        Text("No Results").foregroundStyle(.secondary).padding()
                    }
                }
                .padding(20)
                .padding(.top, onComplete == nil && !reservesActionsSpace ? 0 : 46)

            }
            if let onComplete, let onCancel {
                SceneCreationActions(color: actionColor, onComplete: onComplete, onCancel: onCancel,
                    isValid: true)
                    .padding(.horizontal, 16).padding(.top, 12)
            }
        }
        .frame(width: 380, height: 510)
    }
}

struct SceneCreationActions: View {
    let color: Color
    let onComplete: () -> Void
    let onCancel: () -> Void
    let isValid: Bool
    var isNextStep = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            GlassEffectContainer(spacing: 12) { buttons }
        } else {
            buttons
        }
    }

    private var buttons: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(SceneActionButtonStyle(color: nil, circular: true, addsLegacyShadow: true))
                .accessibilityLabel("Previous Step")
            } else {
                MacMixCircularCloseButton(action: onCancel,
                    usesLiquidGlass: AppAppearanceFeatures.usesLiquidGlass)
            }
            Spacer()
            Button(action: onComplete) {
                if isNextStep {
                    Text("Next Step")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .contentShape(Capsule())
                } else {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(SceneActionButtonStyle(color: color, circular: !isNextStep, addsLegacyShadow: true))
            .accessibilityLabel(isNextStep ? Text("Next Step") : Text("Done"))
            .disabled(!isValid)
        }
    }
}

struct SceneActionButtonStyle: ButtonStyle {
    let color: Color?
    var circular = false
    var usesLiquidGlass = AppAppearanceFeatures.usesLiquidGlass
    var addsLegacyShadow = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: circular ? 100 : 24)
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass, usesLiquidGlass {
            configuration.label
                .foregroundStyle(color == nil ? Color.primary : .white)
                .glassEffect((color.map { Glass.regular.tint($0) } ?? .regular).interactive(isEnabled), in: shape)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        } else {
            configuration.label
                .foregroundStyle(color == nil ? Color.primary : .white)
                .background {
                    if let color { shape.fill(color.gradient) }
                    else { shape.fill(.ultraThinMaterial) }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(addsLegacyShadow ? 0.16 : 0), radius: 4, y: 2)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        }
    }
}

struct MacMixCircularCloseButton: View {
    let action: () -> Void
    let usesLiquidGlass: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(SceneActionButtonStyle(color: nil, circular: true,
                                           usesLiquidGlass: usesLiquidGlass, addsLegacyShadow: true))
        .accessibilityLabel("Cancel")
        .keyboardShortcut(.cancelAction)
    }
}

private struct SceneNameSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SceneSymbolSelectionSurface: View {
    let isSelected: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.primary.opacity(0.08) : .clear)
    }
}
