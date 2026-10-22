import CoreAudio
import Foundation

// A connected receiver selection belongs to the shared HAL output. App routes
// may reuse it, but must never change it on behalf of an individual application.
nonisolated struct AirPlayOutputRoute: Equatable, Sendable {
    let deviceID: AudioObjectID
    let sourceIDs: [UInt32]

    var isConnected: Bool {
        AirPlayDataSources.matchesSelection(sourceIDs, deviceID: deviceID)
    }

    static func validatedUIDs(_ uids: [String], routes: [String: Self]) -> [String] {
        uids.filter { routes[$0]?.isConnected != false }
    }
}

// AirPlay can expose one HAL device with multiple receiver data sources.
// These are receiver choices, not independently routable HAL devices.
nonisolated struct AirPlayDataSources {
    struct Source: Equatable, Sendable {
        let id: UInt32
        let name: String
    }

    let selectedIDs: [UInt32]
    let sources: [Source]

    var selectedName: String? {
        let names = selectedIDs.compactMap { id in sources.first { $0.id == id }?.name }
        // Never label an unknown selection with another receiver's name.
        guard !names.isEmpty, names.count == selectedIDs.count else { return nil }
        return names.joined(separator: ", ")
    }

    // App routing and preference migration require complete selected metadata.
    // Keep the HAL fallback for display, but never pin an unnamed receiver.
    var routingSourceIDs: [UInt32] {
        guard selectedName != nil else { return [] }
        return Array(Set(selectedIDs)).sorted()
    }

    static func read(deviceID: AudioObjectID) -> Self {
        let selected = ids(deviceID: deviceID, selector: kAudioDevicePropertyDataSource) ?? []
        let available = ids(deviceID: deviceID, selector: kAudioDevicePropertyDataSources) ?? []
        var seen = Set<UInt32>()
        let sources = (available + selected).compactMap { id -> Source? in
            guard seen.insert(id).inserted,
                  let name = name(deviceID: deviceID, sourceID: id) else { return nil }
            return Source(id: id, name: name)
        }
        return Self(selectedIDs: selected, sources: sources)
    }

    static func select(_ sourceID: UInt32, deviceID: AudioObjectID) -> Bool {
        if isSelected(sourceID, deviceID: deviceID) { return true }
        // A receiver may have disappeared since the panel last refreshed.
        guard ids(deviceID: deviceID, selector: kAudioDevicePropertyDataSources)?.contains(sourceID) == true else {
            return false
        }
        var address = address(kAudioDevicePropertyDataSource)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value = sourceID
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    static func isSelected(_ sourceID: UInt32, deviceID: AudioObjectID) -> Bool {
        ids(deviceID: deviceID, selector: kAudioDevicePropertyDataSource) == [sourceID]
    }

    static func matchesSelection(_ sourceIDs: [UInt32], deviceID: AudioObjectID) -> Bool {
        guard !sourceIDs.isEmpty,
              let selected = ids(deviceID: deviceID, selector: kAudioDevicePropertyDataSource) else { return false }
        return Array(Set(selected)).sorted() == Array(Set(sourceIDs)).sorted()
    }

    private static func ids(deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> [UInt32]? {
        var address = address(selector)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size % UInt32(MemoryLayout<UInt32>.size) == 0 else { return nil }
        guard size > 0 else { return [] }
        var values = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        let status = values.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr,
              size % UInt32(MemoryLayout<UInt32>.size) == 0,
              Int(size) <= values.count * MemoryLayout<UInt32>.size else { return nil }
        return Array(values.prefix(Int(size) / MemoryLayout<UInt32>.size))
    }

    private static func name(deviceID: AudioObjectID, sourceID: UInt32) -> String? {
        var address = address(kAudioDevicePropertyDataSourceNameForIDCFString)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var sourceID = sourceID
        var result: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &sourceID) { input in
            withUnsafeMutablePointer(to: &result) { output in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(input),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(output),
                    mOutputDataSize: UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                )
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &translation)
            }
        }
        // The translation property returns a retained CFString.
        let name = result?.takeRetainedValue() as String?
        guard status == noErr, let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return name
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }
}
