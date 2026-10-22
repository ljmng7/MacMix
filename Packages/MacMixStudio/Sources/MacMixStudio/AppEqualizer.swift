import Foundation
import AppKit
import Observation
@_exported import MacMixEQDSP

public struct EqualizerConfiguration: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var gains: [Double] = Array(repeating: 0, count: 10)
    public var presetID = "flat"
    public var usesSimpleControls = true
    // Optional for backwards-compatible decoding of existing ten-band presets.
    public var toneGains: [Double]? = nil
    public var normalizedToneGains: [Double]? {
        guard let toneGains, toneGains.count == 3 else { return nil }
        return toneGains.map { $0.isFinite ? max(-12, min(12, $0)) : 0 }
    }
    public init() {}
    public var normalizedGains: [Double] {
        (0..<10).map { index in
            guard gains.indices.contains(index), gains[index].isFinite else { return 0 }
            return max(-12, min(12, gains[index]))
        }
    }
    public mutating func applyPreset(_ preset: EqualizerPreset) {
        gains = preset.gains
        toneGains = preset.toneGains
        presetID = preset.id
        isEnabled = preset.id != "flat"
    }
    public mutating func setBand(_ index: Int, gain: Double) {
        guard (0..<10).contains(index) else { return }
        gains = normalizedGains
        toneGains = nil
        gains[index] = gain.isFinite ? max(-12, min(12, gain)) : 0
        if EqualizerPreset.builtIn.contains(where: { $0.id == presetID }) {
            presetID = "custom"
        }
    }
    // Tone mode uses a low shelf, a broad mid bell and a high shelf. The fitted
    // graphic gains are only a bridge for editing/preset thumbnails; changing the
    // visible control mode never changes which filters are currently sounding.
    public static let groups = [0..<3, 3..<7, 7..<10]
    public func simpleGain(_ index: Int) -> Double {
        guard Self.groups.indices.contains(index) else { return 0 }
        if let tones = normalizedToneGains { return tones[index] }
        let group = Self.groups[index]
        return group.map { normalizedGains[$0] }.reduce(0, +) / Double(group.count)
    }
    public mutating func setSimpleGain(_ index: Int, gain: Double) {
        guard Self.groups.indices.contains(index), gain.isFinite else { return }
        var tones = normalizedToneGains ?? (0..<3).map { simpleGain($0) }
        tones[index] = max(-12, min(12, gain))
        toneGains = tones
        var fitted = [Double](repeating: 0, count: 10)
        tones.withUnsafeBufferPointer { source in
            fitted.withUnsafeMutableBufferPointer { destination in
                MacMixEQFitToneGains(source.baseAddress, destination.baseAddress)
            }
        }
        gains = fitted
        if EqualizerPreset.builtIn.contains(where: { $0.id == presetID }) {
            presetID = "custom"
        }
    }
}

public struct EqualizerPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let gains: [Double]
    public let toneGains: [Double]?
    public init(id: String, name: String, gains: [Double], toneGains: [Double]? = nil) {
        self.id = id; self.name = name; self.gains = gains; self.toneGains = toneGains
    }
    // Original starting curves, not device calibration or copies of another app's presets.
    public static let builtIn: [Self] = [
        .init(id: "flat", name: "Flat (Off)", gains: [0,0,0,0,0,0,0,0,0,0]),
        .init(id: "acoustic", name: "Acoustic", gains: [1,1,0,-1,-1,0,1,2,1,0]),
        .init(id: "bass", name: "Bass Booster", gains: [5,4,3,1,0,0,0,0,0,0]),
        .init(id: "bass-reducer", name: "Bass Reducer", gains: [-5,-4,-3,-1,0,0,0,0,0,0]),
        .init(id: "classical", name: "Classical", gains: [2,2,1,0,-1,-1,0,1,2,2]),
        .init(id: "dance", name: "Dance", gains: [4,3,1,0,-1,1,2,1,2,1]),
        .init(id: "jazz", name: "Jazz", gains: [2,2,0,-1,-1,1,2,1,2,1]),
        .init(id: "pop", name: "Pop", gains: [-1,0,1,2,3,3,2,1,0,-1]),
        .init(id: "rb", name: "R&B", gains: [3,3,2,1,-1,0,1,2,2,1]),
        .init(id: "rock", name: "Rock", gains: [3,2,1,-1,-2,-1,1,2,3,2]),
        .init(id: "treble", name: "Treble Booster", gains: [0,0,0,0,0,0,1,2,3,4]),
        .init(id: "treble-reducer", name: "Treble Reducer", gains: [0,0,0,0,0,0,-1,-2,-3,-4]),
        .init(id: "vocal", name: "Vocal Booster", gains: [-2,-1,0,1,2,3,3,2,0,-1])
    ]
}

@MainActor @Observable
private final class EqualizerConfigurationEntry {
    var value: EqualizerConfiguration
    var isEnabled: Bool
    init(_ value: EqualizerConfiguration) {
        self.value = value
        self.isEnabled = value.isEnabled
    }
}

@MainActor @Observable
public final class AppEqualizerStore {
    @ObservationIgnored public private(set) var configurations: [String: EqualizerConfiguration]
    public private(set) var presets: [EqualizerPreset]
    public var hasAccess = false { didSet { reconcileBoostPreference() } }
    public private(set) var isEnabled: Bool
    public var isFeatureActive: Bool { hasAccess && isEnabled }
    @ObservationIgnored private let boostPreferenceKey: String
    private static let enabledKey = "MacMix.CustomEqualizer.Enabled"
    private static let savedBoostKey = "MacMix.CustomEqualizer.PreviousBoost"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var entries: [String: EqualizerConfigurationEntry] = [:]
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private var configurationsDirty = false
    @ObservationIgnored private var presetsDirty = false
    private static let settingsKey = "MacMix.AppEqualizer.Configurations.v1"
    private static let presetsKey = "MacMix.AppEqualizer.Presets.v1"
    public init(defaults: UserDefaults = .standard, boostPreferenceKey: String = "MacMix.Enables200PercentVolume") {
        self.defaults = defaults
        self.boostPreferenceKey = boostPreferenceKey
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        configurations = defaults.data(forKey: Self.settingsKey).flatMap {
            try? JSONDecoder().decode([String: EqualizerConfiguration].self, from: $0)
        } ?? [:]
        presets = defaults.data(forKey: Self.presetsKey).flatMap {
            try? JSONDecoder().decode([EqualizerPreset].self, from: $0)
        } ?? []
        // Preserve the current sound when loading the retired Spoken Word preset.
        for key in Array(configurations.keys) where configurations[key]?.presetID == "speech" {
            configurations[key]?.presetID = "custom"
            configurationsDirty = true
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }
    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        saveTimer?.invalidate()
    }
    public func updateAccess(_ enabled: Bool) {
        hasAccess = enabled
        reconcileBoostPreference()
    }
    public func setFeatureEnabled(_ enabled: Bool) {
        guard !enabled || hasAccess else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        reconcileBoostPreference()
    }
    private func reconcileBoostPreference() {
        if isFeatureActive {
            if defaults.object(forKey: Self.savedBoostKey) == nil {
                defaults.set(defaults.bool(forKey: boostPreferenceKey), forKey: Self.savedBoostKey)
            }
            if defaults.bool(forKey: boostPreferenceKey) { defaults.set(false, forKey: boostPreferenceKey) }
        } else if defaults.object(forKey: Self.savedBoostKey) != nil {
            let previous = defaults.bool(forKey: Self.savedBoostKey)
            defaults.set(previous, forKey: boostPreferenceKey)
            defaults.removeObject(forKey: Self.savedBoostKey)
        }
    }

    private func entry(for bundleID: String) -> EqualizerConfigurationEntry {
        if let entry = entries[bundleID] { return entry }
        let entry = EqualizerConfigurationEntry(configurations[bundleID] ?? EqualizerConfiguration())
        entries[bundleID] = entry
        return entry
    }
    public func configuration(for bundleID: String) -> EqualizerConfiguration {
        entry(for: bundleID).value
    }
    public func isActive(for bundleID: String) -> Bool {
        isFeatureActive && entry(for: bundleID).isEnabled
    }
    public func set(_ configuration: EqualizerConfiguration, for bundleID: String) {
        var normalized = configuration
        normalized.gains = configuration.normalizedGains
        normalized.toneGains = configuration.normalizedToneGains
        guard normalized != (configurations[bundleID] ?? EqualizerConfiguration()) else { return }
        configurations[bundleID] = normalized
        if let entry = entries[bundleID] {
            if entry.isEnabled != normalized.isEnabled { entry.isEnabled = normalized.isEnabled }
            entry.value = normalized
        }
        configurationsDirty = true
        // Reuse one debounce timer rather than creating/canceling a Task per event.
        if let saveTimer { saveTimer.fireDate = Date().addingTimeInterval(0.25) }
        else {
            let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            saveTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    public func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        if configurationsDirty, let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: Self.settingsKey)
            configurationsDirty = false
        }
        if presetsDirty, let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Self.presetsKey)
            presetsDirty = false
        }
    }
    @discardableResult public func savePreset(name: String, for bundleID: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuration = configuration(for: bundleID)
        guard !name.isEmpty, name.count <= 60, (configuration.presetID == "custom" || presets.contains(where: { $0.id == configuration.presetID })) else { return false }
        let preset = EqualizerPreset(id: UUID().uuidString, name: name, gains: configuration.normalizedGains, toneGains: configuration.normalizedToneGains)
        presets.append(preset)
        presetsDirty = true
        configuration.presetID = preset.id
        set(configuration, for: bundleID)
        flush()
        return true
    }
    /// Editing keeps an app-local snapshot; only this action changes the shared preset.
    @discardableResult public func overwritePreset(for bundleID: String) -> Bool {
        let configuration = configuration(for: bundleID)
        guard let index = presets.firstIndex(where: { $0.id == configuration.presetID }) else { return false }
        let original = presets[index]
        presets[index] = EqualizerPreset(id: original.id, name: original.name,
            gains: configuration.normalizedGains, toneGains: configuration.normalizedToneGains)
        presetsDirty = true
        flush()
        return true
    }

    public func deletePreset(_ id: String) {
        guard presets.contains(where: { $0.id == id }) else { return }
        presets.removeAll { $0.id == id }
        presetsDirty = true
        for key in Array(configurations.keys) where configurations[key]?.presetID == id {
            var configuration = configuration(for: key)
            configuration.presetID = "custom"
            set(configuration, for: key)
        }
        flush()
    }
}
