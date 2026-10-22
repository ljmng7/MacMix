import AppKit
import Foundation

@main
struct AudioSceneStoreTests {
    @MainActor static func main() async {
        let suite = "MacMix.SceneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AudioSceneStore(defaults: defaults)
        precondition(!store.launchesMixedApps, "Automatic app launching defaults to off")
        store.launchesMixedApps = true
        precondition(AudioSceneStore(defaults: defaults).launchesMixedApps, "Auto-launch preference persists")
        let historyDefaults = UserDefaults(suiteName: suite + ".history")!
        defer { historyDefaults.removePersistentDomain(forName: suite + ".history") }
        let historyStore = AudioSceneStore(defaults: historyDefaults)
        let first = AudioScenePreset(name: "First", symbol: "ear", color: "blue")
        let historySecond = AudioScenePreset(name: "Second", symbol: "ear", color: "red")
        let third = AudioScenePreset(name: "Third", symbol: "ear", color: "green")
        historyStore.add(first)
        historyStore.add(historySecond)
        historyStore.add(third)
        historyStore.delete(third.id)
        precondition(historyStore.selection == historySecond.id, "Deletion returns to previous preset, not the first")
        historyStore.selection = nil
        historyStore.selection = historySecond.id
        historyStore.delete(historySecond.id)
        precondition(historyStore.selection == nil, "Deletion returns to default when it was previously used")
        let unavailableScene = AudioScenePreset(name: "Offline", symbol: "headphones", color: "blue",
            output: AudioSceneDevice(uid: "output", name: "Headphones", volume: 0.5),
            input: AudioSceneDevice(uid: "input", name: "Microphone", volume: 0.5))
        precondition(unavailableScene.unavailableDeviceNames(outputUIDs: [], inputUIDs: [])
                     == ["Headphones", "Microphone"], "Both missing device names are retained")
        precondition(unavailableScene.unavailableDeviceNames(outputUIDs: ["output"], inputUIDs: [])
                     == ["Microphone"], "Only unavailable devices are reported")
        precondition(unavailableScene.unavailableDeviceNames(outputUIDs: ["output"], inputUIDs: ["input"]).isEmpty)
        precondition(!AudioSceneApplicationResult.unavailableDevices(["Headphones"]).succeeded,
                     "Unavailable devices must fail scene activation")
        precondition(AudioSceneApplicationResult.deviceList(["A", "B"], language: "zh-Hans") == "A、B")
        precondition(AudioSceneApplicationResult.deviceList(["A", "B"], language: "en") == "A, B")
        precondition(AudioSceneApplicationResult.deviceList(["AirPods Pro 3", "AirPods Pro 3"], language: "zh-Hans") == "AirPods Pro 3")
        precondition(AudioSceneApplicationResult.deviceList(["A", "B", "A"], language: "en") == "A, B",
                     "Deduplicate device labels while preserving their display order")
        precondition(store.showsInPanel && !store.showsMenuBarScene && store.shortcutModifiers == 0,
                     "Scene settings have the requested defaults")
        store.showsInPanel = false
        store.showsMenuBarScene = true
        store.shortcutModifiers = 2
        let restoredSettings = AudioSceneStore(defaults: defaults)
        precondition(!restoredSettings.showsInPanel && restoredSettings.showsMenuBarScene
                     && restoredSettings.shortcutModifiers == 2, "Scene settings survive relaunch")
        let legacyDevice = try! JSONDecoder().decode(AudioSceneDevice.self,
            from: Data(#"{"uid":"legacy","name":"Old Output","volume":0.5}"#.utf8))
        precondition(legacyDevice.listeningMode == nil && legacyDevice.spatialAudioMode == nil
                     && legacyDevice.controlsExpanded == nil, "Older presets retain compatibility")
        precondition(legacyDevice.iconName == nil && legacyDevice.systemIconData == nil,
                     "Presets without cached icons still decode")
        let device = AudioSceneDevice(uid: "persistent-device-uid", name: "Test Output", volume: 0.42)
        var disconnectedDevice = device
        disconnectedDevice.recordVolume(0.9, deviceUID: "fallback-speaker")
        precondition(disconnectedDevice.volume == 0.42, "Fallback device edits must not overwrite an offline preset")
        disconnectedDevice.recordVolume(0.9, deviceUID: nil)
        precondition(disconnectedDevice.volume == 0.42, "Missing devices must not receive panel volume edits")
        disconnectedDevice.recordVolume(0.65, deviceUID: device.uid)
        precondition(disconnectedDevice.volume == 0.65, "Matching device edits must synchronize")
        var draft = AudioScenePreset(name: "Draft", symbol: "headphones", color: "navy")
        draft.name = "  Focus  "
        draft.output = device
        draft.output?.volume = 0.27
        draft.output?.listeningMode = 3
        draft.apps = [AudioSceneApp(id: "draft.app", name: "Draft App", volume: 0.64)]
        let legacyApp = try! JSONDecoder().decode(AudioSceneApp.self,
            from: Data(#"{"id":"old.app","name":"Old App","volume":0.5}"#.utf8))
        precondition(legacyApp.isMuted == nil, "Old mix entries load without a mute field")
        var edited = draft
        edited.output?.controlsExpanded = true
        edited.output?.iconName = "airpodspro"
        precondition(edited.hasSameAudioSettings(as: draft), "Disclosure and icon caching must not trigger audio writes")
        edited.output?.volume = 0.7
        precondition(!edited.hasSameAudioSettings(as: draft), "Device slider edits must trigger live updates")
        edited = draft
        edited.apps[0].isMuted = true
        precondition(!edited.hasSameAudioSettings(as: draft), "Mute edits must trigger live updates")
        let restoredMute = try! JSONDecoder().decode(AudioScenePreset.self, from: JSONEncoder().encode(edited))
        precondition(restoredMute.apps[0].isMuted == true && restoredMute.apps[0].volume == 0.64,
                     "Mute persists without discarding the audible volume")
        precondition(AudioSceneStore(defaults: defaults).presets.isEmpty, "Editing a draft must not persist it")
        precondition(AudioSceneStore(defaults: defaults).selection == nil, "Abandoning either creation step does not activate a scene")
        store.add(draft)
        precondition(store.presets.first?.name == "Focus", "Commit draft with normalized name")
        precondition(store.presets.first?.output?.volume == 0.27
                     && store.presets.first?.output?.listeningMode == 3
                     && store.presets.first?.apps.first?.volume == 0.64,
                     "Completion preserves second-step values instead of replacing them with live device values")
        store.add(draft)
        precondition(store.presets.count == 1, "Duplicate completion must not create another scene")
        // Panel edits only overwrite apps already included in the preset.
        store.presets[0].recordApp(AudioSceneApp(id: "panel.app", name: "Panel App", volume: 0.31, isMuted: false))
        precondition(!store.presets[0].apps.contains { $0.id == "panel.app" },
                     "Panel-only apps must not be added to the preset")
        store.presets[0].recordApp(AudioSceneApp(id: "draft.app", name: "Draft App", volume: 0.31, isMuted: false))
        store.presets[0].recordApp(AudioSceneApp(id: "draft.app", name: "Draft App", volume: 0.31, isMuted: true))
        store.presets[0].output?.isMuted = true
        store.selection = nil
        store.selection = draft.id
        let panelRestored = AudioSceneStore(defaults: defaults)
        precondition(panelRestored.presets[0].apps.count == 1)
        precondition(panelRestored.presets[0].apps.first { $0.id == "draft.app" }?.volume == 0.31)
        precondition(panelRestored.presets[0].apps.first { $0.id == "draft.app" }?.isMuted == true)
        precondition(panelRestored.presets[0].output?.isMuted == true,
                     "System mute and existing app edits survive leaving and reloading the preset")
        var second = draft
        second.id = UUID()
        second.apps[0].volume = 0.82
        store.add(second)
        store.selection = draft.id
        store.presets[0].recordApp(AudioSceneApp(id: "draft.app", name: "Draft App", volume: 0.19, isMuted: false))
        store.selection = second.id
        let isolated = AudioSceneStore(defaults: defaults)
        precondition(isolated.presets.first { $0.id == draft.id }?.apps[0].volume == 0.19)
        precondition(isolated.presets.first { $0.id == second.id }?.apps[0].volume == 0.82,
                     "Editing a shared app in one preset must leave the other preset unchanged")
        store.delete(second.id)
        store.delete(draft.id)
        draft.name = "  \n "
        store.add(draft)
        precondition(store.presets.count == 1 && store.presets[0].usesDefaultName == true,
                     "An empty name creates a numbered scene")
        precondition(store.presets[0].displayName(at: 0) == AudioScenePreset.defaultName(at: 0))
        store.delete(draft.id)
        for _ in 0..<12 { store.add(output: device, input: nil) }
        precondition(store.presets.count == 9, "Enforce maximum scene count")
        store.presets[0].output?.listeningMode = 4
        store.presets[0].output?.spatialAudioMode = 2
        store.presets[0].output?.controlsExpanded = true
        store.presets[0].output?.iconName = "airpodspro"
        store.presets[0].output?.systemIconData = Data([0, 1, 2, 255])
        let controlsRestored = AudioSceneStore(defaults: defaults).presets[0].output
        precondition(controlsRestored?.iconName == "airpodspro"
                     && controlsRestored?.systemIconData == Data([0, 1, 2, 255]),
                     "Persist both the fallback symbol and exact system icon bytes")
        precondition(controlsRestored?.listeningMode == 4 && controlsRestored?.spatialAudioMode == 2
                     && controlsRestored?.controlsExpanded == true, "Restore per-scene Pro Control values and disclosure state")
        precondition(store.presets[1].output?.listeningMode == nil, "Device settings remain isolated between scenes")
        precondition(Set(store.presets.map(\.id)).count == 9, "Stable unique scene identity")
        let presetsBeforeDefault = store.presets
        store.selection = nil
        let defaultRestored = AudioSceneStore(defaults: defaults)
        precondition(defaultRestored.selection == nil, "Restore default mode without selecting the first preset")
        precondition(defaultRestored.presets == presetsBeforeDefault, "Default mode preserves all preset settings")
        store.selection = store.presets.last?.id
        store.presets[0].commitName("  Focus  ", at: 0)
        precondition(store.presets[0].displayName(at: 0) == "Focus")
        precondition(store.presets[1].displayName(at: 1) == AudioScenePreset.defaultName(at: 1))
        store.presets[0].apps = (0..<100).map {
            AudioSceneApp(id: "test.app.\($0)", name: "App \($0)", path: "/Applications/Test.app", volume: 0.7)
        }
        let restored = AudioSceneStore(defaults: defaults)
        precondition(restored.selection == store.selection, "Restore selected scene")
        precondition(restored.presets == store.presets, "Restore nested edits, device UID and arbitrary app records")
        precondition(restored.presets[0].apps.count == 100, "No app count limit")
        var renamed = restored.presets[0]
        renamed.commitName(" \n ", at: 0)
        precondition(renamed.displayName(at: 0) == AudioScenePreset.defaultName(at: 0), "Clearing restores a numbered name immediately")
        precondition(restored.presets[1].displayName(at: 0) == AudioScenePreset.defaultName(at: 0), "Default names follow current button order")
        let selected = store.selection!
        store.delete(selected)
        precondition(store.presets.count == 8 && store.selection != selected)
        store.add(output: nil, input: nil)
        precondition(store.presets.count == 9, "Deletion releases a slot")
        for id in store.presets.map(\.id) { store.delete(id) }
        precondition(store.selection == nil && AudioSceneStore(defaults: defaults).presets.isEmpty)
        defaults.set(Data("invalid".utf8), forKey: "MacMix.AudioScenes.v1")
        precondition(AudioSceneStore(defaults: defaults).presets.isEmpty, "Recover from corrupt persistence")
        let dragDefaults = UserDefaults(suiteName: suite + ".drag")!
        defer { dragDefaults.removePersistentDomain(forName: suite + ".drag") }
        let dragStore = AudioSceneStore(defaults: dragDefaults)
        dragStore.add(output: device, input: nil)
        let beforeDrag = dragDefaults.data(forKey: "MacMix.AudioScenes.v1")
        for step in 1...100 {
            var preset = dragStore.presets[0]
            preset.output?.volume = Double(step) / 100
            dragStore.updateFromAudio(preset, at: 0)
        }
        precondition(dragStore.presets[0].output?.volume == 1, "Drag updates visible scene state immediately")
        precondition(dragDefaults.data(forKey: "MacMix.AudioScenes.v1") == beforeDrag,
                     "Drag must not serialize each intermediate volume")
        try! await Task.sleep(for: .milliseconds(350))
        precondition(AudioSceneStore(defaults: dragDefaults).presets[0].output?.volume == 1,
                     "Idle after dragging persists the final volume")
        var lastEdit = dragStore.presets[0]
        lastEdit.output?.volume = 0.27
        dragStore.updateFromAudio(lastEdit, at: 0)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        precondition(AudioSceneStore(defaults: dragDefaults).presets[0].output?.volume == 0.27,
                     "App termination flushes the final pending drag edit")
        print("AudioSceneStore tests passed")
    }
}
