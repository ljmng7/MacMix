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

// Receivers share the HAL output's AirPlay icon. Their names are the only
// per-receiver hint, so recognise common AirPlay products from them.
nonisolated enum AirPlayReceiverIcon {
    static func symbolName(for name: String) -> String? {
        let text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
        if has(["homepod mini", "homepodmini"]) { return "homepod.mini" }
        if has(["homepod"]) { return "homepod" }
        if has(["apple tv", "appletv"]) { return "appletv" }
        if has(["beats pill", "beatspill"]) { return "beats.pill" }
        if has(["tv", "电视", "bravia", "vizio", "roku"]) { return "tv" }
        if has(["sonos", "bose", "marshall", "denon", "speaker", "soundbar", "音箱", "音响", "回音壁"]) {
            return "hifispeaker"
        }
        return nil
    }
}

// The first output clocks the mixer's aggregate. AirPlay's network clock starves
// drift-compensated outputs, so it leads only when nothing else is routed.
nonisolated enum RoutedOutputClockOrder {
    static func ordered(_ uids: some Sequence<String>, preferred: String, isAirPlay: (String) -> Bool) -> [String] {
        Set(uids).map { (uid: $0, rank: (isAirPlay($0) ? 2 : 0) + ($0 == preferred ? 0 : 1)) }
            .sorted { ($0.rank, $0.uid) < ($1.rank, $1.uid) }
            .map(\.uid)
    }
}

nonisolated struct AirPlayReceiverAdvertisement: Equatable, Sendable {
    let name: String
    let txt: [String: String]
}

// A receiver found on the network, which may have no Core Audio output yet.
nonisolated struct DiscoveredAirPlayReceiver: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let modelID: String?

    var symbolName: String {
        let model = modelID ?? ""
        if model.hasPrefix("AudioAccessory5") { return "homepod.mini" }
        if model.hasPrefix("AudioAccessory") { return "homepod" }
        if model.hasPrefix("AppleTV") { return "appletv" }
        return AirPlayReceiverIcon.symbolName(for: name) ?? "airplayaudio"
    }

    // One service can appear once per network interface.
    static func receivers(from advertisements: [AirPlayReceiverAdvertisement],
                          excludingName computerName: String?) -> [Self] {
        var seen = Set<String>()
        return advertisements.compactMap { advertisement -> Self? in
            guard advertisement.name != computerName, supportsAudio(advertisement.txt) else { return nil }
            let id = advertisement.txt["deviceid"] ?? advertisement.name
            guard seen.insert(id).inserted else { return nil }
            return Self(id: id, name: advertisement.name, modelID: advertisement.txt["model"])
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // Everything found now, plus previous receivers not yet confirmed gone.
    static func retaining(_ previous: [Self], in current: [Self]) -> [Self] {
        let found = Set(current.map(\.id))
        return (current + previous.filter { !found.contains($0.id) })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // Bit 9 of the feature flags marks audio. Keep receivers that omit the flags.
    private static func supportsAudio(_ txt: [String: String]) -> Bool {
        guard let features = txt["features"]?.split(separator: ",").first,
              let flags = UInt64(features.replacingOccurrences(of: "0x", with: ""), radix: 16) else { return true }
        return flags & (1 << 9) != 0
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

    // A connected receiver can also be its own HAL device with no data sources,
    // which routes like any other output.
    static func isSupported(deviceID: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDataSources)
        return AudioObjectHasProperty(deviceID, &address)
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
