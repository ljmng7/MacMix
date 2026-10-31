import SwiftUI
import AppKit
import MacMixStudio

struct AppEqualizerRow: View {
    let app: AudioAppState
    let audioModel: AudioModel
    let maximumVolume: Double
    let layout: AppVolumeRowLayout
    let onToggleMute: () -> Void
    let onVolumeChange: (Double) -> Void
    @AppStorage private var expanded: Bool
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    @AppStorage private var eqSectionExpanded: Bool
    @AppStorage private var outputSectionExpanded: Bool

    init(app: AudioAppState, audioModel: AudioModel, maximumVolume: Double,
         layout: AppVolumeRowLayout, onToggleMute: @escaping () -> Void,
         onVolumeChange: @escaping (Double) -> Void) {
        self.app = app; self.audioModel = audioModel; self.maximumVolume = maximumVolume
        self.layout = layout; self.onToggleMute = onToggleMute; self.onVolumeChange = onVolumeChange
        _expanded = AppStorage(wrappedValue: false, "MacMix.EQ.Expanded.\(app.bundleID)")
        _eqSectionExpanded = AppStorage(wrappedValue: true, "MacMix.EQ.SectionExpanded.\(app.bundleID)")
        _outputSectionExpanded = AppStorage(wrappedValue: false, "MacMix.OutputRouting.Expanded.\(app.bundleID)")
    }
    var body: some View {
        // Each section follows its Advanced setting; a lone section cannot collapse.
        let showsEqualizer = hasStudioAccess && audioModel.equalizerStore.isFeatureActive
        let showsOutput = hasStudioAccess && audioModel.outputRoutingStore.isFeatureActive
        let sectionsCollapse = showsEqualizer && showsOutput
        VStack(spacing: 10) {
            AppVolumeControls(name: app.name, icon: app.icon, volume: app.volume, isMuted: app.isMuted,
                maximumVolume: audioModel.equalizerStore.isFeatureActive ? 1 : maximumVolume,
                layout: layout, audioControlsExpanded: showsEqualizer || showsOutput ? $expanded : nil,
                onToggleMute: onToggleMute, onVolumeChange: onVolumeChange)
            if (showsEqualizer || showsOutput) && expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if showsEqualizer {
                        AppEqualizerPanel(app: app, store: audioModel.equalizerStore,
                                          isExpanded: sectionsCollapse ? $eqSectionExpanded : nil,
                                          usesPresetPopovers: layout == .compact) {
                            audioModel.setEqualizer($0, for: app)
                        }
                    }
                    if sectionsCollapse { Divider() }
                    if showsOutput {
                        AppAudioSectionHeader(title: Text("Output Devices", tableName: "AppOutputRouting"),
                                              isExpanded: sectionsCollapse ? $outputSectionExpanded : nil)
                        if !sectionsCollapse || outputSectionExpanded {
                            AppOutputRoutingPicker(app: app, audioModel: audioModel, layout: layout)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5))
                }
            }
        }
    }
}

private struct EqualizerEditorLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 272)
        // Preserve the simple chart's aspect ratio, insets and label row. Both
        // editors receive this same proposal, so switching cannot resize the panel.
        return CGSize(width: width, height: max(160, (width - 12) / 1.8 + 42))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

private struct AppEqualizerPanel: View {
    let app: AudioAppState
    let store: AppEqualizerStore
    /// `nil` when EQ is the only section, which then stays open.
    let isExpanded: Binding<Bool>?
    var usesPresetPopovers = false
    let onChange: (EqualizerConfiguration) -> Void
    @State private var showsSave = false
    @State private var showsDelete = false
    @State private var presetName = ""
    @State private var presetPopover: PresetPopover?

    private enum PresetPopover: String, Identifiable {
        case save, delete
        var id: String { rawValue }
    }
    private var configuration: EqualizerConfiguration {
        let stored = store.configuration(for: app.bundleID)
        guard stored.isEnabled else {
            var flat = EqualizerConfiguration()
            flat.usesSimpleControls = stored.usesSimpleControls
            return flat
        }
        return stored
    }
    private var selectedPreset: EqualizerPreset? {
        (EqualizerPreset.builtIn + store.presets).first { $0.id == configuration.presetID }
    }
    private var equalizerModePicker: some View {
        Picker("EQ Controls", selection: Binding(get: { configuration.usesSimpleControls }, set: { simple in
            var next = store.configuration(for: app.bundleID)
            next.usesSimpleControls = simple
            onChange(next)
        })) {
            Text("Simple").tag(true)
            Text("Fine").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppAudioSectionHeader(title: Text("EQ"), isExpanded: isExpanded)
            if isExpanded?.wrappedValue ?? true {
                HStack(spacing: 8) {
                    if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
                        equalizerModePicker.buttonBorderShape(.capsule)
                    } else {
                        equalizerModePicker
                    }
                    Spacer(minLength: 4)
                    NativeEqualizerPresetPicker(
                        presets: EqualizerPreset.builtIn + store.presets,
                        userPresetIDs: Set(store.presets.map(\.id)),
                        configuration: configuration,
                        imageForPreset: presetImage,
                        onSelect: { id in
                            guard let preset = (EqualizerPreset.builtIn + store.presets).first(where: { $0.id == id }) else { return }
                            var next = configuration
                            next.applyPreset(preset)
                            onChange(next)
                        },
                        onOverwrite: { store.overwritePreset(for: app.bundleID) },
                        onSave: {
                            if usesPresetPopovers { presetPopover = .save }
                            else { presetName = ""; showsSave = true }
                        },
                        onDelete: {
                            if usesPresetPopovers { presetPopover = .delete }
                            else { showsDelete = true }
                        }
                    )
                    .frame(maxWidth: 165, alignment: .trailing)
                    .popover(item: $presetPopover, arrowEdge: .top) { presentation in
                        switch presentation {
                        case .save:
                            EqualizerPresetNamePopover { name in
                                store.savePreset(name: name, for: app.bundleID)
                            }
                        case .delete:
                            EqualizerPresetDeletePopover {
                                if let preset = selectedPreset { store.deletePreset(preset.id) }
                            }
                        }
                    }
                }

                EqualizerEditorLayout {
                    if configuration.usesSimpleControls {
                        SimpleEqualizerControls(targetID: app.id, configuration: configuration) { index, gain in
                            var next = self.configuration
                            guard store.isFeatureActive else { return }
                            next.isEnabled = true
                            next.setSimpleGain(index, gain: gain)
                            onChange(next)
                        }
                    } else {
                        DetailedEqualizerControls(configuration: configuration) { index, gain in
                            var next = self.configuration
                            guard store.isFeatureActive else { return }
                            next.isEnabled = true
                            next.setBand(index, gain: gain)
                            onChange(next)
                        }

                    }
                }
            }
        }
        .controlSize(.small)
        .alert("Save EQ Preset", isPresented: $showsSave) {
            TextField("Preset Name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.savePreset(name: presetName, for: app.bundleID) }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetName.count > 60)
        } message: {
            Text("This preset will be available to all apps.")
        }
        .alert("Delete EQ Preset?", isPresented: $showsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let preset = selectedPreset { store.deletePreset(preset.id) }
            }
        } message: {
            Text("Apps using this preset will keep their current curve as Custom.")
        }
        .onDisappear { store.flush() }
    }
    private static let presetIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()
    private func presetImage(_ preset: EqualizerPreset) -> NSImage {
        let cacheKey = "\(preset.id):\(preset.gains)" as NSString
        if preset.id != "custom", let cached = Self.presetIcons.object(forKey: cacheKey) {
            return cached
        }
        // Include the saved curve in the key so overwriting a preset refreshes its thumbnail.
        // App-local temporary edits leave the saved preset preview unchanged.
        let image = NSImage(size: NSSize(width: 34, height: 16), flipped: true) { rect in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath()
            for (i, gain) in preset.gains.enumerated() {
                let point = NSPoint(x: 2 + CGFloat(i) * 30 / 9, y: 8 - CGFloat(gain) * 0.5)
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            path.lineWidth = 1.2; path.stroke()
            return true
        }
        image.isTemplate = true
        if preset.id != "custom" { Self.presetIcons.setObject(image, forKey: cacheKey) }
        return image
    }
}

/// Keep text editing and validation local to the presentation, not the live EQ panel.
private struct EqualizerPresetNamePopover: View {
    let onSave: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && trimmedName.count <= 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save EQ Preset").font(.headline)
            Text("This preset will be available to all apps.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Preset Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .tint(.gray)
                    .foregroundStyle(.primary)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 280)
        .onAppear { nameIsFocused = true }
    }

    private func save() {
        guard canSave, onSave(trimmedName) else { return }
        dismiss()
    }
}

private struct EqualizerPresetDeletePopover: View {
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete EQ Preset?").font(.headline)
            Text("Apps using this preset will keep their current curve as Custom.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .tint(.gray)
                    .foregroundStyle(.primary)
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .tint(.red)
                .foregroundStyle(.red)
            }
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 280)
    }
}

private struct EqualizerCurve: Shape {
    let gains: [Double]
    func path(in rect: CGRect) -> Path {
        guard gains.count > 1 else { return Path() }
        let points = gains.enumerated().map { i, gain in
            CGPoint(x: rect.minX + CGFloat(i) * rect.width / CGFloat(gains.count - 1),
                    y: rect.midY - CGFloat(gain / 24) * rect.height)
        }
        return Path { path in
            path.move(to: points[0])
            for i in 1..<points.count {
                let previous = points[i - 1], next = points[i]
                let middle = (previous.x + next.x) / 2
                path.addCurve(to: next, control1: CGPoint(x: middle, y: previous.y),
                              control2: CGPoint(x: middle, y: next.y))
            }
        }
    }
}

private struct SimpleEqualizerCurve: Shape {
    let gains: [Double]
    func path(in rect: CGRect) -> Path {
        guard gains.count == 3 else { return Path() }
        let points = gains.enumerated().map { index, gain in
            CGPoint(x: rect.width * (CGFloat(index) / 3 + 1.0 / 6),
                    y: rect.midY - CGFloat(gain / 24) * rect.height)
        }
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: points[0].y))
            path.addLine(to: points[0])
            for index in 1..<3 {
                let a = points[index - 1], b = points[index]
                let distance = (b.x - a.x) * 0.42
                path.addCurve(to: b, control1: CGPoint(x: a.x + distance, y: a.y),
                              control2: CGPoint(x: b.x - distance, y: b.y))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: points[2].y))
        }
    }
}

private enum SimpleEQBand: Int, CaseIterable, Identifiable {
    case low, mid, high
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self { case .low: "Low"; case .mid: "Mid"; case .high: "High" }
    }
}

private enum EqualizerPalette {
    // sRGB colors sampled from the supplied reference after profile conversion.
    private static let stops: [(Double, Double, Double)] = [
        (254.0/255, 149.0/255, 17.0/255), // orange
        (1, 0.91, 0.31),
        (96.0/255, 247.0/255, 188.0/255), // mint
        (0, 0.94, 0.98),
        (0, 174.0/255, 1) // blue
    ]
    static var outline: Color { .primary.opacity(0.10) }
    static var curve: LinearGradient {
        LinearGradient(colors: stops.map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2) },
                       startPoint: .top, endPoint: .bottom)
    }
    static func handle(_ gain: Double) -> Color {
        let position = max(0, min(4, (12 - gain) / 6))
        let index = min(3, Int(position)), fraction = position - Double(index)
        let a = stops[index], b = stops[index + 1]
        return Color(.sRGB, red: a.0 + (b.0 - a.0) * fraction,
                     green: a.1 + (b.1 - a.1) * fraction, blue: a.2 + (b.2 - a.2) * fraction)
    }
}

private struct EqualizerDragHandle: View {
    let color: Color
    let isDragging: Bool
    let themeColor: Color
    let isEnabled: Bool
    var body: some View {
        ZStack {
            if isDragging {
                if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
                    Color.clear
                        .frame(width: 72, height: 72)
                        .glassEffect(.clear.interactive(), in: Circle())
                        .allowsHitTesting(false)
                } else {
                    Circle().stroke(themeColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            Circle().fill(EqualizerPalette.outline)
                .frame(width: 22, height: 22)
                .opacity(isEnabled ? 1 : 0.45)
            Circle().fill(color)
                .frame(width: 16, height: 16)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
    }
}

private struct SimpleEqualizerControls: View {
    let targetID: String
    let configuration: EqualizerConfiguration
    let onGainChange: (Int, Double) -> Void
    @State private var activeBand: SimpleEQBand?
    @State private var draggedGain: Double?
    @State private var editUpdates = EqualizerEditCoalescer()
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    private var gains: [Double] {
        var values = SimpleEQBand.allCases.map { configuration.simpleGain($0.rawValue) }
        if let activeBand, let draggedGain { values[activeBand.rawValue] = draggedGain }
        return values
    }
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let inset = geometry.size.width / 6
                let travel = geometry.size.height - 24
                let width = geometry.size.width - inset * 2
                ZStack {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .primary.opacity(0.075), location: 0.3),
                                           .init(color: .primary.opacity(0.075), location: 0.7),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: geometry.size.width / 3)
                    Path { path in
                        for index in 0..<3 {
                            let x = inset + CGFloat(index) * width / 2
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                    }
                    .stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.15),
                                                 .init(color: .black, location: 0.85),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    EqualizerSpectrumView(targetID: targetID, isEnabled: true)
                        .accessibilityHidden(true)
                    SimpleEqualizerCurve(gains: gains)
                        .stroke(EqualizerPalette.outline, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .padding(.vertical, 12)
                    SimpleEqualizerCurve(gains: gains)
                        .stroke(EqualizerPalette.curve, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .padding(.vertical, 12)
                    ForEach(SimpleEQBand.allCases) { band in
                        let index = band.rawValue
                        let gain = gains[index]
                        EqualizerDragHandle(color: EqualizerPalette.handle(gain),
                                            isDragging: activeBand == band,
                                            themeColor: accentColor.resolvedColor(hasStudioAccess: hasStudioAccess),
                                            isEnabled: true)
                            .position(x: inset + CGFloat(index) * width / 2,
                                      y: geometry.size.height / 2 - CGFloat(gain / 24) * travel)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("simpleEQ")).onChanged { value in
                                activeBand = band
                                let next = max(-12, min(12, 24 * (0.5 - (value.location.y - 12) / travel)))
                                draggedGain = next
                                let emit = onGainChange
                                editUpdates.submit { emit(index, next) }
                            }.onEnded { _ in
                                editUpdates.flush()
                                activeBand = nil
                                draggedGain = nil
                            })
                            .accessibilityElement()
                            .accessibilityLabel(Text(band.label))
                            .accessibilityValue(Text("\(gain, specifier: "%.1f") dB"))
                            .accessibilityAdjustableAction { direction in
                                update(index, gain + (direction == .increment ? 1 : -1))
                            }
                            .focusable()
                            .focusEffectDisabled()
                            .onKeyPress(.upArrow) { update(index, gain + 1); return .handled }
                            .onKeyPress(.downArrow) { update(index, gain - 1); return .handled }
                    }
                }
                .coordinateSpace(name: "simpleEQ")
            }
            .aspectRatio(1.8, contentMode: .fit)
            HStack {
                ForEach(SimpleEQBand.allCases) { band in
                    VStack(spacing: 2) {
                        Text(band.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onDisappear { editUpdates.flush() }
    }
    private func update(_ index: Int, _ gain: Double) {
        editUpdates.flush()
        onGainChange(index, gain)
    }
}

private enum EQBand: Int, CaseIterable, Identifiable {
    case hz32, hz64, hz125, hz250, hz500, hz1000, hz2000, hz4000, hz8000, hz16000
    var id: Self { self }
    var label: String { ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"][rawValue] }
}
private struct DetailedEqualizerControls: View {
    let configuration: EqualizerConfiguration
    let onBandChange: (Int, Double) -> Void
    var body: some View {
        HStack(spacing: 2) {
            ForEach(EQBand.allCases) { band in
                EqualizerBandControl(label: band.label, gain: configuration.normalizedGains[band.rawValue]) { gain in
                    onBandChange(band.rawValue, gain)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
private struct EqualizerBandControl: View {
    let label: String
    let gain: Double
    let onChange: (Double) -> Void
    @Environment(\.hasStudioAccess) private var hasStudioAccess
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system

    var body: some View {
        VStack(spacing: 6) {
            Text(Int(gain.rounded()), format: .number)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
            NativeEqualizerSlider(label: label, gain: gain,
                                  tint: accentColor.resolvedColor(hasStudioAccess: hasStudioAccess),
                                  onChange: onChange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(verbatim: label).font(.system(size: 10).monospacedDigit())
            Text(verbatim: "Hz").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NativeEqualizerSlider: NSViewRepresentable {
    let label: String
    let gain: Double
    let tint: Color
    let onChange: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> EqualizerSystemSlider {
        let slider = EqualizerSystemSlider(frame: NSRect(x: 0, y: 0, width: 24, height: 128))
        slider.sliderType = .linear
        slider.isVertical = true
        slider.minValue = -12
        slider.maxValue = 12
        slider.doubleValue = gain
        context.coordinator.previousValue = gain
        slider.isContinuous = true
        slider.controlSize = .small
        slider.focusRingType = .none
        slider.numberOfTickMarks = 1 // AppKit places a single tick at the midpoint (0 dB).
        slider.tickMarkPosition = .trailing
        slider.allowsTickMarkValuesOnly = false
        slider.altIncrementValue = 0.1
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.onTrackingEnded = { [weak coordinator = context.coordinator] in coordinator?.updates.flush() }
        slider.setContentHuggingPriority(.defaultLow, for: .vertical)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            slider.neutralValue = 0
            slider.tintProminence = .primary
        }
        return slider
    }

    func updateNSView(_ slider: EqualizerSystemSlider, context: Context) {
        context.coordinator.onChange = onChange
        if slider.isEnabled != isEnabled { slider.isEnabled = isEnabled }
        let fillColor = NSColor(tint)
        if slider.trackFillColor?.isEqual(fillColor) != true { slider.trackFillColor = fillColor }
        let accessibilityLabel = "\(label) Hz"
        if slider.accessibilityLabel() != accessibilityLabel { slider.setAccessibilityLabel(accessibilityLabel) }
        // Native tracking owns the thumb until it ends. A delayed SwiftUI update
        // must not pull it back to an earlier position during a held drag.
        if !slider.isTracking {
            if slider.doubleValue != gain { slider.doubleValue = gain }
            context.coordinator.previousValue = gain
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerSystemSlider, context: Context) -> CGSize? {
        CGSize(width: min(24, proposal.width ?? 24), height: proposal.height ?? 128)
    }

    static func dismantleNSView(_ slider: EqualizerSystemSlider, coordinator: Coordinator) {
        slider.onTrackingEnded = nil
        slider.target = nil
        // Flush outside SwiftUI's teardown transaction, using the latest model callback.
        Task { @MainActor in coordinator.updates.flush() }
    }

    @MainActor final class Coordinator: NSObject {
        var onChange: (Double) -> Void
        var previousValue = 0.0
        let updates = EqualizerEditCoalescer()
        init(onChange: @escaping (Double) -> Void) { self.onChange = onChange }

        @objc func valueChanged(_ slider: EqualizerSystemSlider) {
            let raw = max(-12, min(12, slider.doubleValue))
            let value = abs(raw) < 0.2 ? 0 : raw
            if slider.isTracking,
               (previousValue < 0 && value >= 0) || (previousValue > 0 && value <= 0) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if slider.doubleValue != value { slider.doubleValue = value }
            guard value != previousValue else { return }
            previousValue = value
            if slider.isTracking {
                updates.submit { [weak self] in self?.onChange(value) }
            } else {
                updates.cancel()
                onChange(value)
            }
        }
    }
}

/// Keep AppKit's complete tracking, keyboard, accessibility and drawing behavior.
/// The flag only prevents stale model updates from interrupting native tracking.
private final class EqualizerSystemSlider: NSSlider {
    private(set) var isTracking = false
    var onTrackingEnded: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Touch tracking need not pass through mouseDown; control events cover
        // both pointer and touch. They fire after the first action, so mouseDown
        // still marks pointer tracking first.
        if #available(macOS 27.0, *) {
            addTarget(self, action: #selector(trackingBegan), for: .trackingBegan)
            addTarget(self, action: #selector(trackingEnded),
                      for: [.trackingEndedInside, .trackingEndedOutside, .trackingCancelled])
        }
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityValueDescription() -> String? {
        // Format only when accessibility asks, rather than for every mouse event.
        let rounded = (doubleValue * 10).rounded() / 10
        let value = rounded == 0 ? 0 : rounded
        return "\(value.formatted(.number.precision(.fractionLength(1)))) dB"
    }
    override func mouseDown(with event: NSEvent) {
        setTracking(true)
        defer { setTracking(false) }
        super.mouseDown(with: event)
    }

    @objc private func trackingBegan(_ sender: NSSlider) { setTracking(true) }
    @objc private func trackingEnded(_ sender: NSSlider) { setTracking(false) }

    private func setTracking(_ tracking: Bool) {
        guard isTracking != tracking else { return }
        isTracking = tracking
        if !tracking { onTrackingEnded?() }
    }
}

