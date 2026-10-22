import AppKit
import CoreAudio
import Foundation
import Observation

// Module-local HAL functions shadow CoreAudio in this test executable only.
// Tests exercise the production translation and array readers without touching
// any real audio devices or changing the test machine's output.
nonisolated enum FakeHAL {
    nonisolated(unsafe) static var selected: [UInt32] = [7]
    nonisolated(unsafe) static var available: [UInt32] = [7, 9]
    nonisolated(unsafe) static var names: [UInt32: String] = [7: "Living Room HomePod", 9: "Bedroom HomePod"]
    nonisolated(unsafe) static var supported = true
    nonisolated(unsafe) static var settable = true
    nonisolated(unsafe) static var readFails = false
    nonisolated(unsafe) static var malformedSize = false
    nonisolated(unsafe) static var writes: [UInt32] = []
    nonisolated(unsafe) static var maskWrites: [(UInt64, Bool)] = []

    static func values(_ selector: AudioObjectPropertySelector) -> [UInt32] {
        selector == kAudioDevicePropertyDataSource ? selected : available
    }
}

nonisolated func AudioObjectHasProperty(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>) -> Bool {
    precondition(address.pointee.mScope == kAudioDevicePropertyScopeOutput)
    return FakeHAL.supported
}

nonisolated func AudioObjectGetPropertyDataSize(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>) -> OSStatus {
    size.pointee = FakeHAL.malformedSize ? 3 : UInt32(FakeHAL.values(address.pointee.mSelector).count * 4)
    return FakeHAL.readFails ? -1 : noErr
}

nonisolated func AudioObjectGetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>,
    _ data: UnsafeMutableRawPointer) -> OSStatus {
    guard !FakeHAL.readFails else { return -1 }
    if address.pointee.mSelector == kAudioDevicePropertyDataSourceNameForIDCFString {
        let translation = data.assumingMemoryBound(to: AudioValueTranslation.self).pointee
        let sourceID = translation.mInputData.assumingMemoryBound(to: UInt32.self).pointee
        guard let name = FakeHAL.names[sourceID] else { return -1 }
        translation.mOutputData.assumingMemoryBound(to: Unmanaged<CFString>?.self).pointee =
            Unmanaged.passRetained(name as CFString)
    } else {
        let values = FakeHAL.values(address.pointee.mSelector)
        guard size.pointee >= UInt32(values.count * 4) else { return -1 }
        for (index, value) in values.enumerated() {
            data.assumingMemoryBound(to: UInt32.self)[index] = value
        }
        size.pointee = UInt32(values.count * 4)
    }
    return noErr
}

nonisolated func AudioObjectIsPropertySettable(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ settable: UnsafeMutablePointer<DarwinBoolean>) -> OSStatus {
    settable.pointee = DarwinBoolean(FakeHAL.settable)
    return noErr
}

nonisolated func AudioObjectSetPropertyData(_ id: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ data: UnsafeRawPointer) -> OSStatus {
    precondition(address.pointee.mSelector == kAudioDevicePropertyDataSource && size == 4)
    let sourceID = data.assumingMemoryBound(to: UInt32.self).pointee
    FakeHAL.writes.append(sourceID)
    FakeHAL.selected = [sourceID]
    return noErr
}

struct AudioDeviceBattery: Equatable {}
struct AudioAccessoryControlState: Equatable {}

nonisolated func MacMixAudioIOContextSetDestinationMask(_ context: Int, _ index: Int,
    _ mask: UInt64, _ initializeBeforeStart: Bool) {
    precondition(index == 0)
    FakeHAL.maskWrites.append((mask, initializeBeforeStart))
}

@main struct AirPlayAudioRoutesTests {
    @MainActor static func main() {
        let snapshot = AirPlayDataSources.read(deviceID: 100)
        precondition(snapshot.sources.map(\.id) == [7, 9])
        precondition(snapshot.selectedName == "Living Room HomePod")
        FakeHAL.selected = [7, 9]
        precondition(AirPlayDataSources.read(deviceID: 100).selectedName == "Living Room HomePod, Bedroom HomePod")
        precondition(!AirPlayDataSources.isSelected(7, deviceID: 100), "A group is not the requested single receiver")

        FakeHAL.available = [7, 7]
        precondition(AirPlayDataSources.read(deviceID: 100).sources.map(\.id) == [7, 9], "Deduplicate and retain selected receivers absent from available list")
        FakeHAL.names.removeValue(forKey: 9)
        precondition(AirPlayDataSources.read(deviceID: 100).selectedName == nil, "Do not mislabel a partially unknown group")
        FakeHAL.names[9] = "   "
        precondition(AirPlayDataSources.read(deviceID: 100).sources.count == 1)

        FakeHAL.supported = false
        precondition(AirPlayDataSources.read(deviceID: 100).sources.isEmpty)
        FakeHAL.supported = true
        FakeHAL.malformedSize = true
        precondition(AirPlayDataSources.read(deviceID: 100).sources.isEmpty)
        FakeHAL.malformedSize = false
        FakeHAL.readFails = true
        precondition(AirPlayDataSources.read(deviceID: 100).selectedName == nil)
        FakeHAL.readFails = false

        FakeHAL.available = [7, 9]
        FakeHAL.selected = [7]
        precondition(!AirPlayDataSources.select(99, deviceID: 100) && FakeHAL.writes.isEmpty)
        FakeHAL.settable = false
        precondition(!AirPlayDataSources.select(9, deviceID: 100) && FakeHAL.writes.isEmpty)
        precondition(AirPlayDataSources.select(7, deviceID: 100), "Already selected does not require a write")
        FakeHAL.settable = true
        precondition(AirPlayDataSources.select(9, deviceID: 100))
        precondition(AirPlayDataSources.isSelected(9, deviceID: 100) && FakeHAL.writes == [9])

        let state = OutputAudioState()
        let base = device(name: "AirPlay", current: true)
        var living = device(name: "Living Room HomePod", current: false)
        living.dataSourceID = 7
        var bedroom = device(name: "Bedroom HomePod", current: true)
        bedroom.dataSourceID = 9
        precondition(living.id == bedroom.id && living.uid == bedroom.uid)
        precondition(living.selectionID != bedroom.selectionID)
        precondition(living != bedroom)
        state.devices = [base]
        state.airPlayDestinations = [living, bedroom]
        precondition(state.selectionDevices.count == 2)
        precondition(state.selectionDevices[0].volume == nil)
        precondition(state.selectionDevices[1].volume == 0.5)
        state.devices[0].volume = 0.8
        precondition(state.selectionDevices[1].volume == 0.8, "Receiver rows reflect live hardware volume")
        state.airPlayDestinations = []
        precondition(state.selectionDevices == state.devices, "Missing data sources retain the HAL row")

        // Active group members remain highlighted, but clicking one must switch
        // to that single receiver rather than short-circuit as already selected.
        living = device(name: "Living Room HomePod", current: true)
        living.dataSourceID = 7
        bedroom = device(name: "Bedroom HomePod", current: true)
        bedroom.dataSourceID = 9
        state.devices = [base] // A group has no single selected source ID.
        state.airPlayDestinations = [living, bedroom]
        precondition(state.selectionDevices.allSatisfy(\.isCurrent))
        precondition(!state.isSelected(living) && !state.isSelected(bedroom))
        var single = base
        single.dataSourceID = 7
        state.devices = [single]
        precondition(state.isSelected(living) && !state.isSelected(bedroom))

        let hardware = CoreAudioHardware()
        state.devices = [base]
        FakeHAL.selected = [9]
        FakeHAL.names = [7: "Living Room HomePod"]
        state.airPlayDestinations = hardware.airPlayDestinations(in: state.devices)
        precondition(state.selectionDevices == state.devices, "Unknown active receiver preserves the current HAL row even when another receiver is named")
        FakeHAL.selected = [7, 9]
        state.airPlayDestinations = hardware.airPlayDestinations(in: state.devices)
        precondition(state.selectionDevices == state.devices, "Partially unknown group must not appear as just its known member")
        FakeHAL.selected = []
        state.airPlayDestinations = hardware.airPlayDestinations(in: state.devices)
        precondition(state.selectionDevices == state.devices, "Unreadable active selection preserves the HAL row")
        FakeHAL.selected = [7, 9]
        FakeHAL.names[9] = "Bedroom HomePod"
        state.airPlayDestinations = hardware.airPlayDestinations(in: state.devices)
        precondition(state.selectionDevices.count == 2 && state.selectionDevices.allSatisfy(\.isCurrent))
        precondition(!state.isSelected(state.selectionDevices[0]), "A production-expanded group member can switch to a single receiver")

        var group = base
        group.selectedDataSourceIDs = [7, 9]
        state.devices = [group]
        precondition(state.routingDevices.count == 1, "A shared HAL receiver group is one app output")
        precondition(state.routingDestinations[0].dataSourceIDs == [7, 9])
        group.selectedDataSourceIDs = []
        state.devices = [group]
        precondition(state.routingDevices.isEmpty, "Do not offer an unreadable or unconnected receiver")

        FakeHAL.selected = [9, 7]
        let route = AirPlayOutputRoute(deviceID: 100, sourceIDs: [7, 9])
        precondition(route.isConnected, "Receiver group order is not significant")
        precondition(AirPlayOutputRoute.validatedUIDs(["local", "airplay-hal"], routes: ["airplay-hal": route]) == ["local", "airplay-hal"])
        FakeHAL.selected = [9]
        precondition(AirPlayOutputRoute.validatedUIDs(["local", "airplay-hal"], routes: ["airplay-hal": route]) == ["local"], "A changed receiver must not steal the old app route; local output remains")
        precondition(!AirPlayOutputRoute(deviceID: 100, sourceIDs: []).isConnected)
        FakeHAL.readFails = true
        precondition(!AirPlayOutputRoute(deviceID: 100, sourceIDs: [9]).isConnected)
        FakeHAL.readFails = false
        precondition(AirPlayOutputRoute.validatedUIDs(["local", "airplay-hal"], routes: ["airplay-hal": AirPlayOutputRoute(deviceID: 100, sourceIDs: [9])]) == ["local", "airplay-hal"], "Transient read failures must recover when the same receiver is readable again")
        precondition(FakeHAL.writes == [9], "App route validation never changes the shared receiver")

        let runningMixer = RunningMixerMaskProbe()
        runningMixer.silenceChangedAirPlayReceivers()
        precondition(FakeHAL.maskWrites.count == 1 && FakeHAL.maskWrites[0].0 == 1)
        precondition(!FakeHAL.maskWrites[0].1, "A running engine must publish an atomic mask, never write callback-owned gains")
        precondition(runningMixer.outputRoutes["music"] == ["local"], "Rendered route cache must match the published mask")
        runningMixer.silenceChangedAirPlayReceivers()
        precondition(FakeHAL.maskWrites.count == 1, "Do not repeat writes after the stale receiver is removed")

        let domain = "MacMix.Incomplete.AirPlay.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppOutputRoutingStore(defaults: defaults)
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        store.setSelected(true, destination: .init(uid: "airplay-hal", name: "AirPlay"), for: "music")
        FakeHAL.selected = [7, 9]
        FakeHAL.names = [7: "Living Room HomePod"]
        let incomplete = AirPlayDataSources.read(deviceID: 100)
        precondition(incomplete.selectedName == nil && incomplete.routingSourceIDs.isEmpty)
        group.selectedDataSourceIDs = incomplete.routingSourceIDs
        state.devices = [group]
        precondition(state.routingDestinations.isEmpty, "A partially unnamed group must not be offered to app routing")
        store.bindLegacyAirPlayDestinations(state.routingDestinations)
        precondition(store.destinations(for: "music")[0].dataSourceIDs == nil, "Do not permanently migrate a legacy preference using incomplete names")
        FakeHAL.selected = [9]
        precondition(AirPlayDataSources.read(deviceID: 100).routingSourceIDs.isEmpty, "An unnamed single receiver is also unreadable")
        FakeHAL.selected = [9, 7]
        FakeHAL.names[9] = "Bedroom HomePod"
        group.selectedDataSourceIDs = AirPlayDataSources.read(deviceID: 100).routingSourceIDs
        state.devices = [group]
        store.bindLegacyAirPlayDestinations(state.routingDestinations)
        precondition(store.destinations(for: "music")[0].dataSourceIDs == [7, 9], "Complete recovered metadata enables migration")
        print("AirPlay route regression tests passed")
    }

    static func device(name: String, current: Bool) -> AudioDevice {
        AudioDevice(id: 100, uid: "airplay-hal", name: name, manufacturer: nil, modelUID: nil,
            iconName: "airplayaudio", systemIconURL: nil, systemIcon: nil,
            transportType: kAudioDeviceTransportTypeAirPlay, isCurrent: current, volume: 0.5)
    }
}
