import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

struct AudioScenesPage: View {
    let audioModel: AudioModel
    let isStudioEnabled: Bool
    private var store: AudioSceneStore { audioModel.sceneStore }

    @State private var creationWindow = SceneCreationWindowController()
    @State private var creationAnchor: NSView?
    @State private var scenePageAnchor: NSView?
    @State private var showsActivationHelp = false
    @State private var editingSceneID: UUID?
    @State private var pendingDeleteID: UUID?
    @State private var movesForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("MacMix.AudioScenes.HasShownActivationHelp") private var hasShownActivationHelp = false
    @AppStorage(ThemePreference.accentColor) private var accent: ThemeAccentColor = .system

    private var activeSelection: Binding<UUID?> {
        Binding(get: { editingSceneID ?? store.selection }, set: selectScene)
    }

    var body: some View {
        @Bindable var store = store
        ZStack {
            Group {
            if !isStudioEnabled {
                Edition.shared.studioPrompt(.scenesPage)
            } else {
                if let id = editingSceneID ?? store.selection, let index = store.presets.firstIndex(where: { $0.id == id }) {
                    AudioSceneEditor(scene: sceneBinding(id), sceneIndex: index, audio: audioModel, unavailableNames: missingDevices(store.presets[index]), onDelete: {
                        deleteScene(id)
                    })
                        .id(id)
                        .disabled(!isStudioEnabled)
                } else {
                    GeometryReader { geometry in
                        Form {
                            if !store.presets.isEmpty {
                                SceneGeneralSettings(audio: audioModel)
                            }
                            Section {
                            } header: {
                                VStack(spacing: 18) {
                                    Image("app.3.stack.3d")
                                        .font(.system(size: 54, weight: .light))
                                        .foregroundStyle(.secondary)
                                    Text("Scene Presets").font(.title2.bold()).foregroundStyle(.primary)
                                    if store.presets.isEmpty {
                                        Text("Create your first scene").font(.body).foregroundStyle(.secondary)
                                        creationButton(size: 68)
                                            .padding(.top, 10)
                                    } else {
                                        Text("Scene presets are off. Go to the panel to control audio.")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, max(32, (geometry.size.height - (store.presets.isEmpty ? 0 : 260)) * 0.20))
                            }
                        }
                        .formStyle(.grouped)
                    }
                }
            }
        }
            .id(editingSceneID ?? store.selection)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .modifier(active: ScenePageSlide(progress: 1, isInsertion: true),
                                     identity: ScenePageSlide(progress: 0, isInsertion: true)),
                removal: .modifier(active: ScenePageSlide(progress: 1, isInsertion: false),
                                   identity: ScenePageSlide(progress: 0, isInsertion: false))))
        }
        .environment(\.scenePageMovesForward, movesForward)
        .onChange(of: store.selection) { oldID, newID in
            if editingSceneID == nil, oldID == nil || store.presets.contains(where: { $0.id == oldID }) {
                setTransitionDirection(from: oldID, to: newID)
            }
        }
        .animation(.smooth(duration: reduceMotion ? 0.16 : 0.32), value: editingSceneID ?? store.selection)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isStudioEnabled && !store.presets.isEmpty {
                SceneSelectionRow(presets: store.presets, selection: activeSelection, onDelete: { pendingDeleteID = $0 }) {
                        SceneDefaultButton(selection: activeSelection,
                                           color: accent.resolvedColor(hasStudioAccess: isStudioEnabled))
                            .popover(isPresented: $showsActivationHelp, arrowEdge: .bottom) {
                                Text("Click a scene label to activate its preset.\nClick here to turn scene presets off.")
                                    .multilineTextAlignment(.center)
                                    .font(.body)
                                    .padding(16)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 320)
                            }
                } trailing: {
                        creationButton(size: 36)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(SceneWindowAnchor { scenePageAnchor = $0 })
        .onDisappear { creationWindow.dismiss() }
        .onChange(of: audioModel.outputState.devices, initial: true) { _, devices in
            cacheDeviceIcons(devices, at: \.output)
        }
        .onChange(of: audioModel.inputState.devices, initial: true) { _, devices in
            cacheDeviceIcons(devices, at: \.input)
        }
        .onChange(of: isStudioEnabled) { _, enabled in
            if !enabled {
                creationWindow.dismiss()
                showsActivationHelp = false
            }
        }
        .confirmationDialog("Delete Scene?", isPresented: Binding(
            get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { deleteScene(id) }
                pendingDeleteID = nil
            }
        }
        .navigationTitle("Scene Presets")
        .tint(accent.resolvedColor(hasStudioAccess: isStudioEnabled))
    }

    @ViewBuilder
    private func creationButton(size: CGFloat) -> some View {
        if store.presets.count >= AudioSceneStore.limit {
            SceneLimitButton(size: size)
        } else {
            Button {
                guard let creationAnchor else { return }
                let draft = AudioScenePreset(
                    name: "",
                    symbol: AudioSceneAppearance.symbols.randomElement() ?? "headphones",
                    color: AudioSceneAppearance.colorIDs.randomElement() ?? "blue",
                    output: audioModel.currentOutputDevice.map { audioModel.sceneDevicePreset($0, direction: .output) },
                    input: audioModel.currentInputDevice.map { audioModel.sceneDevicePreset($0, direction: .input) }
                )
                creationWindow.present(from: creationAnchor, centeredIn: scenePageAnchor, scene: draft,
                    defaultName: AudioScenePreset.defaultName(at: store.presets.count),
                    color: accent.resolvedColor(hasStudioAccess: isStudioEnabled),
                    audio: audioModel, sceneIndex: store.presets.count) { preset in
                    let isFirstScene = store.presets.isEmpty
                    store.add(preset)
                    selectScene(preset.id)
                    if isFirstScene && !hasShownActivationHelp {
                        hasShownActivationHelp = true
                        showsActivationHelp = true
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
            .buttonStyle(SceneActionButtonStyle(color: nil, circular: true))
            .modifier(SceneSurfaceShadow())
            .accessibilityLabel("New Scene")
            .disabled(!isStudioEnabled)
            .background(SceneWindowAnchor { creationAnchor = $0 })
            .opacity(creationWindow.isPresented ? 0 : 1)
            .allowsHitTesting(!creationWindow.isPresented)
        }
    }

    private func deleteScene(_ id: UUID) {
        let wasSelected = store.selection == id || audioModel.activeSceneID == id
        let target = wasSelected ? store.previousSelection(excluding: id) : store.selection
        setTransitionDirection(from: editingSceneID ?? store.selection, to: target)
        store.delete(id)
        if editingSceneID == id { editingSceneID = nil }
        if wasSelected { audioModel.selectScene(target) }
    }

    private func setTransitionDirection(from oldID: UUID?, to newID: UUID?) {
        let oldIndex = store.presets.firstIndex(where: { $0.id == oldID }) ?? -1
        let newIndex = store.presets.firstIndex(where: { $0.id == newID }) ?? -1
        movesForward = newIndex > oldIndex
    }

    private func selectScene(_ id: UUID?) {
        guard isStudioEnabled else { return }
        showsActivationHelp = false
        setTransitionDirection(from: editingSceneID ?? store.selection, to: id)
        editingSceneID = id
        if let id, let scene = store.presets.first(where: { $0.id == id }),
           !missingDevices(scene).isEmpty { return }
        audioModel.selectScene(id)
    }

    private func missingDevices(_ scene: AudioScenePreset) -> [String] {
        scene.unavailableDeviceNames(outputUIDs: Set(audioModel.outputState.devices.map(\.uid)),
                                     inputUIDs: Set(audioModel.inputState.devices.map(\.uid)))
    }

    private func sceneBinding(_ id: UUID) -> Binding<AudioScenePreset> {
        let fallback = store.presets.first { $0.id == id }!
        return Binding(get: { store.presets.first { $0.id == id } ?? fallback }, set: { updated in
            guard let index = store.presets.firstIndex(where: { $0.id == id }) else { return }
            let previous = store.presets[index]
            store.presets[index] = updated
            guard isStudioEnabled, (editingSceneID ?? store.selection) == id,
                  missingDevices(updated).isEmpty,
                  !updated.hasSameAudioSettings(as: previous) else { return }
            if !audioModel.applySceneEdits(updated, previous: previous) { selectScene(id) }
        })
    }

    private func cacheDeviceIcons(_ devices: [AudioDevice], at keyPath: WritableKeyPath<AudioScenePreset, AudioSceneDevice?>) {
        for index in store.presets.indices {
            guard var saved = store.presets[index][keyPath: keyPath],
                  let device = devices.first(where: { $0.uid == saved.uid }) else { continue }
            let symbolChanged = saved.iconName != device.iconName
            guard symbolChanged || (saved.systemIconData == nil && device.systemIcon != nil) else { continue }
            saved.iconName = device.iconName
            if let data = device.systemIcon?.tiffRepresentation {
                saved.systemIconData = data
            } else if symbolChanged {
                saved.systemIconData = nil
            }
            store.presets[index][keyPath: keyPath] = saved
        }
    }
}

private struct ScenePageDirectionKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var scenePageMovesForward: Bool {
        get { self[ScenePageDirectionKey.self] }
        set { self[ScenePageDirectionKey.self] = newValue }
    }
}

// Keep the transition itself stable. Both the retained outgoing page and the
// incoming page read this switch's direction from their common parent.
private struct ScenePageSlide: AnimatableModifier {
    var progress: CGFloat
    let isInsertion: Bool
    @Environment(\.scenePageMovesForward) private var movesForward

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let direction: CGFloat = (movesForward == isInsertion) ? 1 : -1
        content.visualEffect { effect, geometry in
            effect.offset(x: geometry.size.width * direction * progress)
                .opacity(1 - progress)
        }
    }
}

private struct SceneGeneralSettings: View {
    let audio: AudioModel

    var body: some View {
        @Bindable var store = audio.sceneStore
        Section {
            Toggle("Show at Top of Panel", isOn: $store.showsInPanel)
            Toggle("Show Scene in Menu Bar Icon", isOn: $store.showsMenuBarScene)
            Toggle("Automatically Launch Mixed Apps", isOn: $store.launchesMixedApps)
            Picker("Global Shortcuts", selection: Binding(
                get: { SceneShortcutModifiers(rawValue: store.shortcutModifiers) ?? .controlOption },
                set: { audio.changeSceneShortcut($0) }
            )) {
                ForEach(SceneShortcutModifiers.allCases) { modifiers in
                    Text(verbatim: shortcutLabel(modifiers)).tag(modifiers)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("General")
        } footer: {
            Text("1–9 activate scenes in order. 0 turns scenes off.")
            if audio.sceneShortcuts.hasConflict {
                Text("These shortcuts are unavailable. Choose another combination.")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .toggleStyle(.switch)
    }

    private func shortcutLabel(_ modifiers: SceneShortcutModifiers) -> String {
        modifiers == .disabled ? modifiers.label : modifiers.label + " 0–9"
    }
}

struct ScenePanelSelectionRow: View {
    let audio: AudioModel
    var trailingEdgeExtension: CGFloat = 16
    var compact = false
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    @AppStorage(ThemePreference.accentColor) private var accent: ThemeAccentColor = .system

    var body: some View {
        if hasStudioAccess && audio.sceneStore.showsInPanel && !audio.sceneStore.presets.isEmpty {
            SceneSelectionRow(presets: audio.sceneStore.presets, selection: selection,
                              hasTrailingAction: false, trailingEdgeExtension: trailingEdgeExtension) {
                SceneDefaultButton(selection: selection, color: accent.resolvedColor(hasStudioAccess: true))
            } trailing: {
                EmptyView()
            }
            .environment(\.sceneButtonsAreCompact, compact)
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { audio.sceneStore.selection }, set: { audio.selectScene($0) })
    }
}

// Both panels use the scene page's complete row; only the trailing action differs.
private struct SceneSelectionRow<DefaultButton: View, Trailing: View>: View {
    let presets: [AudioScenePreset]
    @Binding var selection: UUID?
    var onDelete: ((UUID) -> Void)? = nil
    var hasTrailingAction = true
    var trailingEdgeExtension: CGFloat = 0
    @ViewBuilder let defaultButton: () -> DefaultButton
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            SceneSelectionBar(presets: presets, selection: $selection, onDelete: onDelete, hasTrailingAction: hasTrailingAction)
                .padding(.trailing, -trailingEdgeExtension)
            HStack {
                defaultButton()
                Spacer(minLength: 0)
                trailing()
            }
            .zIndex(1)
        }
        .padding(.vertical, 4)
        .zIndex(1)
    }
}

private struct SceneLimitButton: View {
    let size: CGFloat
    @State private var showsLimit = false

    var body: some View {
        SceneDisabledPlus(size: size)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .overlay {
                // The visible control is natively disabled; this separate target
                // only explains the limit and never invokes scene creation.
                Button { showsLimit = true } label: {
                    Color.clear.contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Scene")
                .accessibilityHint("You can add up to 9 scenes!")
            }
            .popover(isPresented: $showsLimit, arrowEdge: .bottom) {
                Text("You can add up to 9 scenes!")
                    .multilineTextAlignment(.center)
                    .padding(16)
            }
    }
}

private struct SceneDisabledPlus: View {
    let size: CGFloat
    @State private var nativeSize = CGSize(width: 36, height: 36)

    var body: some View {
        Group {
            if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
                Button {} label: { glyph }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            } else {
                Button {} label: { glyph }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
        }
        .controlSize(.large)
        .disabled(true)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { nativeSize = $0 }
        .scaleEffect(x: size / max(nativeSize.width, 1),
                     y: size / max(nativeSize.height, 1))
        .frame(width: size, height: size)
    }

    private var glyph: some View {
        Image(systemName: "plus")
            .font(.system(size: size * 0.4, weight: .medium))
            // Cancel the surface scaling for the glyph, keeping the same 14.4 pt
            // symbol as the enabled 36 pt button while retaining native styling.
            .scaleEffect(x: nativeSize.width / size, y: nativeSize.height / size)
            .frame(width: 16, height: 16)
    }
}

private struct SceneButtonsCompactKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var sceneButtonsAreCompact: Bool {
        get { self[SceneButtonsCompactKey.self] }
        set { self[SceneButtonsCompactKey.self] = newValue }
    }
}

private struct SceneDefaultButton: View {
    @Binding var selection: UUID?
    let color: Color
    @Environment(\.sceneButtonsAreCompact) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { selection = nil } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                .contentShape(Circle())
        }
        .buttonStyle(SceneActionButtonStyle(color: selection == nil ? color : nil, circular: true))
        .modifier(SceneSelectionShadow(color: color, progress: selection == nil ? 1 : 0))
        .accessibilityLabel("Default")
        .accessibilityAddTraits(selection == nil ? .isSelected : [])
        .help("Default")
        .animation(.smooth(duration: reduceMotion ? 0.16 : 0.32), value: selection)
    }
}

private struct SceneSelectionBar: View {
    let presets: [AudioScenePreset]
    @Binding var selection: UUID?
    var onDelete: ((UUID) -> Void)? = nil
    var hasTrailingAction = true
    @Environment(\.sceneButtonsAreCompact) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            SceneSelectionGroup(presets: presets, selection: $selection, onDelete: onDelete)
            .padding(.leading, compact ? 48 : 54)
            .padding(.trailing, hasTrailingAction ? 54 : 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(height: compact ? 54 : 60)
        .mask { SceneSelectionEdgeMask(hasTrailingAction: hasTrailingAction).padding(.vertical, -24) }
        .animation(.smooth(duration: reduceMotion ? 0.16 : 0.32), value: selection)
        .animation(.smooth(duration: reduceMotion ? 0.16 : 0.32), value: presets.map(\.id))
    }
}

private struct SceneSelectionEdgeMask: View {
    var hasTrailingAction = true
    @Environment(\.sceneButtonsAreCompact) private var compact
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            // Finish fading at the midpoint of each 36 pt floating button.
            let fadeEnd = min(compact ? 30 : 36, width / 3)
            let fadeStart = max(fadeEnd - 18, 0)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: fadeStart / width),
                .init(color: .black, location: fadeEnd / width),
                .init(color: .black, location: 1 - (hasTrailingAction ? fadeEnd : min(18, width / 3)) / width),
                .init(color: .clear, location: hasTrailingAction ? 1 - fadeStart / width : 1),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

private struct SceneSelectionGroup: View {
    let presets: [AudioScenePreset]
    @Binding var selection: UUID?
    var onDelete: ((UUID) -> Void)? = nil

    var body: some View {
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            GlassEffectContainer(spacing: 10) {
                SceneSelectionButtons(presets: presets, selection: $selection, onDelete: onDelete)
            }
        } else {
            SceneSelectionButtons(presets: presets, selection: $selection, onDelete: onDelete)
        }
    }
}

private struct SceneSelectionButtons: View {
    let presets: [AudioScenePreset]
    @Binding var selection: UUID?
    var onDelete: ((UUID) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(presets.enumerated()), id: \.element.id) { index, scene in
                SceneSelectionButton(name: scene.displayName(at: index), symbol: scene.symbol,
                                     color: SceneAppearance.color(scene.color),
                                     isSelected: selection == scene.id,
                                     progress: selection == scene.id ? 1 : 0) {
                    selection = scene.id
                }
                .contextMenu {
                    if let onDelete {
                        Button("Enable", systemImage: "checkmark.circle") { selection = scene.id }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(scene.id) }
                    }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
    }
}

@Animatable
private struct SceneSelectionButton: View {
    @AnimatableIgnored @Environment(\.sceneButtonsAreCompact) private var compact
    @AnimatableIgnored let name: String
    @AnimatableIgnored let symbol: String
    @AnimatableIgnored let color: Color
    @AnimatableIgnored let isSelected: Bool
    var progress: CGFloat
    @AnimatableIgnored let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                SceneLabelRevealLayout(progress: progress) {
                    SceneButtonName(name: name)
                        .padding(.trailing, compact ? 10 : 14)
                }
                .clipped()
                .opacity(progress)
            }
            .frame(height: compact ? 30 : 36)
            .contentShape(Capsule())
        }
        .buttonStyle(SceneSelectionButtonStyle(color: color, progress: progress))
        .modifier(SceneSelectionShadow(color: color, progress: progress))
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(name)
        // The enclosing Animatable view supplies each frame. Do not start separate
        // implicit animations for the label, layout, shadow or glass surface.
        .transaction { $0.animation = nil }
    }
}

private struct SceneSelectionShadow: ViewModifier {
    let color: Color
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.background {
            // GlassEffectContainer renders glass separately from the label. Give
            // the shadow its own full-size silhouette instead of shadowing glyphs.
            Capsule()
                .fill(color)
                .shadow(color: color.opacity(0.4),
                        radius: ScenePresentationFeatures.shadowRadius,
                        y: ScenePresentationFeatures.shadowOffset)
                .overlay {
                    Capsule().fill(.black).blendMode(.destinationOut)
                }
                .compositingGroup()
                .opacity(progress)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct SceneButtonName: View {
    let name: String
    @Environment(\.sceneButtonsAreCompact) private var compact

    var body: some View {
        SceneFadingName(name: name, maximumWidth: compact ? SceneFadingName.menuBarMaximumWidth : 112)
            .font(compact ? .system(size: 12, weight: .semibold) : .body.weight(.semibold))
    }
}

struct SceneFadingName: View {
    static let menuBarMaximumWidth: CGFloat = 80
    let name: String
    var maximumWidth: CGFloat = menuBarMaximumWidth
    private let fadeWidth: CGFloat = 18

    var body: some View {
        SceneNameWidthLayout(maximumWidth: maximumWidth) {
        Text(verbatim: name)
            .fixedSize(horizontal: true, vertical: true)
            .mask {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width > maximumWidth ? fadeWidth : 0)
                    }
                    .frame(width: min(geometry.size.width, maximumWidth), height: geometry.size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .clipped()
    }
}

private struct SceneNameWidthLayout: Layout {
    let maximumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: min(size.width, maximumWidth), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                             anchor: .leading, proposal: .unspecified)
    }
}

// Receives the same interpolated progress as text opacity and the button surface.
private struct SceneLabelRevealLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: size.width * progress, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                              anchor: .center, proposal: .unspecified)
    }
}

private struct SceneSelectionButtonStyle: ButtonStyle {
    let color: Color
    let progress: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        if #available(macOS 15.0, *) {
            return Color.primary.mix(with: .white, by: progress)
        } else {
            let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            var resolved = NSColor.labelColor
            appearance?.performAsCurrentDrawingAppearance {
                resolved = NSColor.labelColor.blended(withFraction: progress, of: .white) ?? .labelColor
            }
            return Color(nsColor: resolved)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        Group {
            if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
                configuration.label
                    .glassEffect(.regular.tint(color.opacity(progress)).interactive(), in: shape)
            } else {
                configuration.label
                    .background {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                            .overlay { shape.fill(color.opacity(progress)) }
                    }
                    .overlay {
                        shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    }
            }
        }
        .foregroundStyle(foregroundColor)
        .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct AudioSceneEditor: View {
    @Binding var scene: AudioScenePreset
    let sceneIndex: Int
    let audio: AudioModel
    var isCreating = false
    var unavailableNames: [String] = []
    var onDelete: (() -> Void)? = nil
    @State private var confirmDelete = false

    var body: some View {
        Form {
            SceneDeviceSection(selection: $scene.output, direction: .output, audio: audio) {
                if !isCreating {
                    if !unavailableNames.isEmpty {
                        Text("\(AudioSceneApplicationResult.deviceList(unavailableNames, language: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)) is unavailable. This preset is not enabled.")
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    SceneIdentityEditor(scene: $scene, sceneIndex: sceneIndex)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)
                }
            }
            SceneDeviceSection(selection: $scene.input, direction: .input, audio: audio) {
                EmptyView()
            }
            SceneMixerSections(apps: $scene.apps, audio: audio, editsDraft: isCreating || !unavailableNames.isEmpty)
            if !isCreating, onDelete != nil {
                Section {
                } footer: {
                    SceneDeleteButton { confirmDelete = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .modifier(SceneCreationFormBackground(isCreating: isCreating))
        .confirmationDialog("Delete Scene?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete?() }
        }
    }
}

private struct SceneDeleteButton: View {
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            Button(role: .destructive, action: action) {
                Text("Delete")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(role: .destructive, action: action) {
                Text("Delete")
                    .font(.body)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }
}

private struct SceneCreationFormBackground: ViewModifier {
    let isCreating: Bool

    func body(content: Content) -> some View {
        if isCreating {
            if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
                content
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 58, for: .scrollContent)
                    .scrollEdgeEffectHidden(true, for: .top)
            } else {
                content
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 58, for: .scrollContent)
            }
        } else {
            content
        }
    }
}

private struct SceneIdentityEditor: View {
    @Binding var scene: AudioScenePreset
    let sceneIndex: Int
    @State private var showsAppearance = false
    @State private var nameDraft = ""

    private var appearancePresentation: Binding<Bool> {
        Binding(get: { showsAppearance }, set: { presented in
            if !presented && showsAppearance {
                scene.commitName(nameDraft, at: sceneIndex)
            }
            showsAppearance = presented
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                nameDraft = scene.usesDefaultName == true ? "" : scene.name
                showsAppearance = true
            } label: {
                Image(systemName: scene.symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(SceneAppearance.color(scene.color).gradient, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: SceneAppearance.color(scene.color).opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit Scene")
            .popover(isPresented: appearancePresentation, arrowEdge: .trailing) {
                SceneAppearanceEditor(scene: $scene, nameDraft: $nameDraft,
                                      defaultName: AudioScenePreset.defaultName(at: sceneIndex))
            }
            Text(scene.displayName(at: sceneIndex))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 16)
    }
}

private struct SceneDeviceSection<Header: View>: View {
    @Binding var selection: AudioSceneDevice?
    let direction: AudioDeviceDirection
    let audio: AudioModel
    @ViewBuilder let identityHeader: () -> Header
    @State private var isExpanded = false

    private var devices: [AudioDevice] {
        direction == .output ? audio.outputState.devices : audio.inputState.devices
    }

    private var visibleDevices: [AudioDevice] {
        isExpanded ? devices : devices.filter { $0.uid == selection?.uid }
    }

    var body: some View {
        let visibleDevices = visibleDevices
        Section {
            if let selection, !devices.contains(where: { $0.uid == selection.uid }) {
                SceneUnavailableDeviceRow(selection: selection, direction: direction)
            } else if selection == nil && !isExpanded {
                EmptyRow(iconName: "questionmark.circle", title: "Select Device")
            }
            ForEach(visibleDevices, id: \.uid) { device in
                SceneDeviceRow(selection: $selection, device: device, direction: direction, audio: audio) {
                    withAnimation(.smooth(duration: 0.24)) {
                        if selection?.uid != device.uid {
                            selection = audio.sceneDevicePreset(device, direction: direction)
                        }
                        isExpanded = false
                    }
                }
                .transition(.opacity)
            }
            if isExpanded && devices.isEmpty {
                EmptyRow(iconName: "questionmark.circle", title: "No available devices")
            }
        } header: {
            VStack(alignment: .leading, spacing: 28) {
                identityHeader()
                CollapsibleHeader(title: direction == .output ? "Output" : "Input", isExpanded: $isExpanded)
            }
        }
    }
}

private struct SceneDeviceRowHeight: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var height = 36.0

    func body(content: Content) -> some View {
        content.frame(minHeight: height)
    }
}

private struct SceneUnavailableDeviceRow: View {
    let selection: AudioSceneDevice
    let direction: AudioDeviceDirection
    @State private var cachedIcon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            DeviceIcon(symbolName: selection.iconName ?? (direction == .output ? "speaker.wave.2.fill" : "mic.fill"),
                       systemIcon: cachedIcon, isCurrent: false)
            Text(selection.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("Unavailable").foregroundStyle(.secondary)
            }
        }
        .modifier(SceneDeviceRowHeight())
        .task(id: selection.systemIconData) {
            cachedIcon = selection.systemIconData.flatMap { NSImage(data: $0) }
        }
    }
}

private struct SceneDeviceRow: View {
    @Binding var selection: AudioSceneDevice?
    let device: AudioDevice
    let direction: AudioDeviceDirection
    let audio: AudioModel
    let onSelect: () -> Void
    @AppStorage(AccessoryDetailsVisibilityPreference.showsAccessoryDetails) private var showsAccessoryDetails = true

    private var isSelected: Bool { selection?.uid == device.uid }
    private var supportsVolume: Bool {
        if device.isCurrent {
            return direction == .output ? audio.outputState.systemVolume != nil : audio.inputState.inputVolume != nil
        }
        return device.volume != nil
    }
    private var battery: AudioDeviceBattery? {
        direction == .output ? audio.outputState.batteryByDeviceUID[device.uid] : nil
    }
    private var controls: AudioAccessoryControlState? {
        guard direction == .output,
              let current = audio.outputState.accessoryControlsByDeviceUID[device.uid] else { return nil }
        return AudioAccessoryControlState(
            supportedListeningModes: current.supportedListeningModes,
            listeningMode: selection?.listeningMode.flatMap(ListeningMode.init(rawValue:)) ?? current.listeningMode,
            supportsSpatialAudio: current.supportsSpatialAudio,
            spatialAudioContentKind: current.spatialAudioContentKind,
            spatialAudioMode: selection?.spatialAudioMode.flatMap(SpatialAudioMode.init(rawValue:)) ?? current.spatialAudioMode,
            canSetSpatialAudio: current.canSetSpatialAudio
        )
    }
    private var volume: Double { isSelected ? (selection?.volume ?? 1) : (device.volume ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onSelect) {
                    HStack(spacing: 12) {
                        DeviceIcon(symbolName: device.iconName, systemIcon: device.systemIcon, isCurrent: isSelected)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.body.weight(.medium)).lineLimit(1)
                            if showsAccessoryDetails, let battery, battery.hasValue {
                                DeviceBatterySummary(deviceSymbolName: device.iconName, battery: battery)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isSelected {
                    Slider(value: Binding(get: { volume }, set: { selection?.volume = $0 }), in: 0...1)
                        .labelsHidden()
                        .frame(width: 220)
                        .disabled(!supportsVolume)
                        .accessibilityLabel("Volume")
                }
                Text(supportsVolume ? volume.formatted(.percent.precision(.fractionLength(0))) : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                if direction == .output && showsAccessoryDetails {
                    Group {
                        if isSelected, controls != nil {
                            Button {
                                withAnimation(.smooth(duration: 0.24)) {
                                    selection?.controlsExpanded = !(selection?.controlsExpanded ?? false)
                                }
                            } label: {
                                Image(systemName: selection?.controlsExpanded == true ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(device.name))
                            .accessibilityValue(selection?.controlsExpanded == true ? Text("Expanded") : Text("Collapsed"))
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                    .frame(width: 18, height: 28)
                }
            }
            .modifier(SceneDeviceRowHeight())
            if isSelected, showsAccessoryDetails, selection?.controlsExpanded == true, let controls {
                AudioAccessoryControlsPanel(state: controls, presentation: .plain,
                    onSetListeningMode: { selection?.listeningMode = $0.rawValue },
                    onSetSpatialAudioMode: { selection?.spatialAudioMode = $0.rawValue })
            }
        }
    }
}

private struct SceneMixerSections: View {
    @Binding var apps: [AudioSceneApp]
    let audio: AudioModel
    var editsDraft = false
    @State private var pickerAnchor: NSView?
    @AppStorage(MixVolumePreference.enables200PercentVolume) private var boosted = false
    private var maximum: Double { boosted ? 2 : 1 }
    private static let listTransitionAnimation = Animation.smooth(duration: 0.22)

    private var currentApps: [AudioAppState] {
        let mixedIDs = Set(apps.map(\.id))
        return audio.outputAppsState.apps.filter { !mixedIDs.contains($0.bundleID) }
    }

    var body: some View {
        let currentApps = currentApps
        Section("Mix") {
            if apps.isEmpty {
                EmptyRow(iconName: "app.dashed", title: "No apps specified in the mix")
                    .transition(.opacity)
            }
            ForEach($apps) { $app in
                SceneSavedAppRow(app: $app, maximum: maximum) {
                    withAnimation(Self.listTransitionAnimation) {
                        apps.removeAll { $0.id == app.id }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        Section("Current") {
            if currentApps.isEmpty {
                EmptyRow(iconName: "app.dashed", title: "No current audio apps")
                    .transition(.opacity)
            }
            ForEach(currentApps) { app in
                SceneCurrentAppRow(app: app, maximum: maximum, audio: audio, editsDraft: editsDraft) { selectedApp in
                    withAnimation(Self.listTransitionAnimation) {
                        apps.append(AudioSceneApp(id: selectedApp.bundleID, name: selectedApp.name,
                            path: NSWorkspace.shared.urlForApplication(withBundleIdentifier: selectedApp.bundleID)?.path,
                            volume: selectedApp.volume, isMuted: selectedApp.isMuted))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Button("Choose Other App…", action: chooseApps)
                .foregroundStyle(.primary)
                .tint(.secondary)
                .background(SceneWindowAnchor { pickerAnchor = $0 })
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            withAnimation(Self.listTransitionAnimation) {
                for url in panel.urls {
                    let bundle = Bundle(url: url)
                    let id = bundle?.bundleIdentifier ?? url.path
                    guard !apps.contains(where: { $0.id == id }) else { continue }
                    apps.append(AudioSceneApp(id: id, name: FileManager.default.displayName(atPath: url.path), path: url.path, volume: 1))
                }
            }
        }
        if let window = pickerAnchor?.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

private struct SceneCurrentAppRow: View {
    let app: AudioAppState
    let maximum: Double
    let audio: AudioModel
    let editsDraft: Bool
    let onAdd: (AudioAppState) -> Void
    @State private var draftApp: AudioAppState

    init(app: AudioAppState, maximum: Double, audio: AudioModel, editsDraft: Bool,
         onAdd: @escaping (AudioAppState) -> Void) {
        self.app = app
        self.maximum = maximum
        self.audio = audio
        self.editsDraft = editsDraft
        self.onAdd = onAdd
        _draftApp = State(initialValue: AudioAppState(app: app.snapshot))
    }

    var body: some View {
        let displayedApp = editsDraft ? draftApp : app
        HStack(spacing: 12) {
            AppVolumeRow(app: displayedApp, maximumVolume: maximum, layout: .controlPanel,
                         onToggleMute: { target in
                             if editsDraft { draftApp.isMuted.toggle() }
                             else { audio.toggleAppMute(target) }
                         }, onVolumeChange: { volume, target in
                             if editsDraft { draftApp.volume = volume }
                             else { audio.setAppVolume(volume, for: target) }
                         })
            SceneMixActionButton(isAdding: true) { onAdd(displayedApp) }
        }
    }
}

private struct SceneSavedAppRow: View {
    @Binding var app: AudioSceneApp
    let maximum: Double
    let onRemove: () -> Void
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            AppVolumeControls(name: app.name, icon: icon, volume: app.volume, isMuted: app.isMuted ?? false,
                              maximumVolume: maximum, layout: .controlPanel,
                              onToggleMute: { app.isMuted = !(app.isMuted ?? false) },
                              onVolumeChange: { app.volume = $0; app.isMuted = false })
            SceneMixActionButton(isAdding: false, action: onRemove)
        }
        .task(id: app.path) {
            if let path = app.path { icon = NSWorkspace.shared.icon(forFile: path) }
            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) { icon = NSWorkspace.shared.icon(forFile: url.path) }
        }
    }
}

private struct SceneMixActionButton: View {
    let isAdding: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAdding ? "plus" : "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(isAdding ? Color.red : Color.green, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAdding ? Text("Add to Mix") : Text("Remove from Mix"))
        .help(isAdding ? Text("Add to Mix") : Text("Remove from Mix"))
    }
}
