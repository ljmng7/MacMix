import AppKit
import Foundation
import Observation

struct AudioSceneDevice: Codable, Equatable {
    var uid: String
    var name: String
    var volume: Double
    var listeningMode: UInt32? = nil
    var spatialAudioMode: UInt8? = nil
    var controlsExpanded: Bool? = nil
    var iconName: String? = nil
    var systemIconData: Data? = nil
    var isMuted: Bool? = nil

    mutating func recordVolume(_ value: Double, deviceUID: String?) {
        guard uid == deviceUID else { return }
        volume = value
    }

    func hasSameAudioSettings(as other: Self) -> Bool {
        uid == other.uid && volume == other.volume
            && listeningMode == other.listeningMode && spatialAudioMode == other.spatialAudioMode
            && isMuted == other.isMuted
    }
}

enum AudioSceneApplicationResult: Equatable {
    case applied, unavailableDevices([String]), failed

    var succeeded: Bool { self == .applied }

    var message: String {
        switch self {
        case .applied: String(localized: "Scene applied.")
        case .unavailableDevices(let names):
            String(localized: "Scene switch failed.\nUnavailable devices: \(Self.deviceList(names, language: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)).")
        case .failed: String(localized: "Scene could not be applied.")
        }
    }

    static func deviceList(_ names: [String], language: String) -> String {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
            .joined(separator: language.hasPrefix("zh") ? "、" : ", ")
    }
}

struct AudioSceneApp: Codable, Identifiable, Equatable {
    var id: String // Bundle identifier survives process restarts.
    var name: String
    var path: String?
    var volume: Double
    var isMuted: Bool? = nil
}

struct AudioScenePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var color: String
    var output: AudioSceneDevice?
    var input: AudioSceneDevice?
    var apps: [AudioSceneApp] = []
    var usesDefaultName: Bool? = nil

    mutating func recordApp(_ app: AudioSceneApp) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = app.volume
            apps[index].isMuted = app.isMuted
        }
    }

    func unavailableDeviceNames(outputUIDs: Set<String>, inputUIDs: Set<String>) -> [String] {
        var names: [String] = []
        if let output, !outputUIDs.contains(output.uid) { names.append(output.name) }
        if let input, !inputUIDs.contains(input.uid) { names.append(input.name) }
        return names
    }

    func hasSameAudioSettings(as other: Self) -> Bool {
        func same(_ lhs: AudioSceneDevice?, _ rhs: AudioSceneDevice?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): true
            case let (lhs?, rhs?): lhs.hasSameAudioSettings(as: rhs)
            default: false
            }
        }
        return same(output, other.output) && same(input, other.input) && apps == other.apps
    }

    func displayName(at index: Int) -> String {
        usesDefaultName == true ? Self.defaultName(at: index) : name
    }

    static func defaultName(at index: Int) -> String {
        String(localized: "Scene \(index + 1)", comment: "Default scene name; number is its one-based position in the scene buttons.")
    }

    mutating func commitName(_ draft: String, at index: Int) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        usesDefaultName = trimmed.isEmpty
        name = trimmed.isEmpty ? Self.defaultName(at: index) : trimmed
    }
}

@MainActor @Observable
final class AudioSceneStore {
    static let limit = 9
    var launchesMixedApps: Bool { didSet { defaults.set(launchesMixedApps, forKey: "MacMix.AudioScenes.LaunchesMixedApps") } }
    var showsInPanel: Bool { didSet { defaults.set(showsInPanel, forKey: "MacMix.AudioScenes.ShowsInPanel") } }
    var showsMenuBarScene: Bool { didSet { defaults.set(showsMenuBarScene, forKey: "MacMix.AudioScenes.ShowsMenuBarScene") } }
    var shortcutModifiers: Int { didSet { defaults.set(shortcutModifiers, forKey: "MacMix.AudioScenes.ShortcutModifiers") } }
    var presets: [AudioScenePreset] { didSet { persist() } }
    var selection: UUID? {
        didSet {
            if oldValue != selection { selectionHistory.append(oldValue) }
            defaults.set(selection?.uuidString ?? Self.defaultSelection, forKey: Self.selectionKey)
        }
    }
    private var selectionHistory: [UUID?] = []
    @ObservationIgnored private var defersAudioPersistence = false
    @ObservationIgnored private var persistenceTimer: Timer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    private static let key = "MacMix.AudioScenes.v1"
    private static let selectionKey = "MacMix.AudioScenes.Selection"
    private static let defaultSelection = "default"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchesMixedApps = defaults.bool(forKey: "MacMix.AudioScenes.LaunchesMixedApps")
        showsInPanel = defaults.object(forKey: "MacMix.AudioScenes.ShowsInPanel") as? Bool ?? true
        showsMenuBarScene = defaults.bool(forKey: "MacMix.AudioScenes.ShowsMenuBarScene")
        shortcutModifiers = defaults.integer(forKey: "MacMix.AudioScenes.ShortcutModifiers")
        presets = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([AudioScenePreset].self, from: $0) }
            .map { Array($0.prefix(Self.limit)) } ?? []
        for index in presets.indices where presets[index].usesDefaultName == nil {
            let name = presets[index].name
            if name == String(localized: "New Scene") || name == "New Scene" || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                presets[index].commitName("", at: index)
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingAudioEdits() }
        }
        let savedSelection = defaults.string(forKey: Self.selectionKey)
        let restoredSelection = savedSelection.flatMap(UUID.init(uuidString:))
        selection = savedSelection == Self.defaultSelection ? nil
            : (presets.first(where: { $0.id == restoredSelection })?.id ?? presets.first?.id)
    }

    func add(output: AudioSceneDevice?, input: AudioSceneDevice?) {
        guard presets.count < Self.limit else { return }
        let preset = AudioScenePreset(
            name: "",
            symbol: AudioSceneAppearance.symbols.randomElement() ?? "headphones",
            color: AudioSceneAppearance.colorIDs.randomElement() ?? "purple",
            output: output,
            input: input
        )
        add(preset)
    }

    func add(_ preset: AudioScenePreset) {
        guard presets.count < Self.limit, !presets.contains(where: { $0.id == preset.id }) else { return }
        var preset = preset
        preset.commitName(preset.usesDefaultName == true ? "" : preset.name, at: presets.count)
        presets.append(preset)
        selection = preset.id
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if selection == id { selection = previousSelection(excluding: id) }
        selectionHistory.removeAll { $0 == id }
    }

    func previousSelection(excluding id: UUID) -> UUID? {
        for previous in selectionHistory.reversed() {
            guard let previous else { return nil }
            if previous != id, presets.contains(where: { $0.id == previous }) { return previous }
        }
        return nil
    }

    deinit {
        persistenceTimer?.invalidate()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    // Audio controls update in memory immediately; repeated drag edits share one save.
    func updateFromAudio(_ preset: AudioScenePreset, at index: Int) {
        defersAudioPersistence = true
        presets[index] = preset
        defersAudioPersistence = false
        persistenceTimer?.invalidate()
        persistenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingAudioEdits() }
        }
        // A menu-bar slider tracks in a different run-loop mode.
        if let persistenceTimer { RunLoop.main.add(persistenceTimer, forMode: .common) }
    }

    func flushPendingAudioEdits() {
        guard persistenceTimer != nil else { return }
        persist()
    }

    private func persist() {
        guard !defersAudioPersistence else { return }
        persistenceTimer?.invalidate()
        persistenceTimer = nil
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

enum AudioSceneAppearance {
    static let colorIDs = ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray", "sage", "coral", "navy"]
    static let symbols = ["headphones", "headphones.circle.fill", "speaker.wave.2.fill", "speaker.fill", "speaker.slash.fill", "mic.fill", "mic.circle.fill", "music.note", "music.note.list", "music.mic", "waveform", "waveform.circle.fill", "hifispeaker.fill", "airpodspro", "ear", "desktopcomputer", "laptopcomputer", "display", "keyboard.fill", "computermouse.fill", "iphone", "ipad", "applewatch", "printer.fill", "externaldrive.fill", "cpu", "network", "wifi", "gamecontroller.fill", "dpad.fill", "dice.fill", "puzzlepiece.fill", "videoprojector.fill", "video.fill", "camera.fill", "film.fill", "tv.fill", "play.rectangle.fill", "house.fill", "building.2.fill", "briefcase.fill", "sofa.fill", "lamp.desk.fill", "lightbulb.fill", "wrench.and.screwdriver.fill", "hammer.fill", "book.fill", "books.vertical.fill", "graduationcap.fill", "pencil", "pencil.and.outline", "doc.text.fill", "newspaper.fill", "moon.fill", "moon.stars.fill", "sun.max.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "bed.double.fill", "sparkles", "cup.and.saucer.fill", "mug.fill", "fork.knife", "wineglass.fill", "birthday.cake.fill", "carrot.fill", "heart.fill", "star.fill", "bolt.fill", "circle.fill", "triangle.fill", "square.fill", "hexagon.fill", "diamond.fill", "flag.fill", "gift.fill", "leaf.fill", "tree.fill", "pawprint.fill", "bird.fill", "fish.fill", "mountain.2.fill", "tent.fill", "flame.fill", "drop.fill", "car.fill", "bicycle", "tram.fill", "airplane", "bus.fill", "ferry.fill", "sailboat.fill", "suitcase.fill", "figure.walk", "figure.run", "figure.yoga", "figure.mind.and.body", "dumbbell.fill", "sportscourt.fill", "basketball.fill", "football.fill", "tennisball.fill", "map.fill", "location.fill", "globe", "clock.fill", "timer", "calendar", "bell.fill", "pin.fill", "compass.drawing"]
}
