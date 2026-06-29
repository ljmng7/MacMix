//
//  CoreAudioHardware.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

struct CoreAudioHardware {
    func devices(for direction: AudioDeviceDirection) -> [AudioDevice] {
        let defaultID = defaultDeviceID(for: direction)

        return audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )
        .filter { hasStreams(deviceID: $0, direction: direction) }
        .compactMap { deviceID in
            let name = stringProperty(deviceID, selector: kAudioObjectPropertyName)
                ?? String(localized: "Unknown Device", comment: "Fallback audio device name when Core Audio does not provide one.")
            let identity = AudioDeviceIdentity(
                name: name,
                manufacturer: stringProperty(deviceID, selector: kAudioObjectPropertyManufacturer),
                modelUID: stringProperty(deviceID, selector: kAudioDevicePropertyModelUID),
                deviceUID: stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                transportType: uint32Property(deviceID, selector: kAudioDevicePropertyTransportType)
            )

            guard !isHidden(deviceID), !identity.isMacMixInternalMixer else {
                return nil
            }

            return AudioDevice(
                id: deviceID,
                uid: identity.deviceUID ?? "\(deviceID)",
                name: name,
                iconName: iconName(for: identity, direction: direction),
                isCurrent: deviceID == defaultID,
                volume: volume(for: deviceID, direction: direction)
            )
        }
    }

    func defaultDeviceID(for direction: AudioDeviceDirection) -> AudioObjectID? {
        var address = propertyAddress(selector: direction.defaultDeviceSelector)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    func setDefaultDevice(_ deviceID: AudioObjectID, direction: AudioDeviceDirection) {
        setSystemDevice(deviceID, selector: direction.defaultDeviceSelector)

        if direction == .output {
            setSystemDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        }
    }

    func volume(for deviceID: AudioObjectID, direction: AudioDeviceDirection) -> Double? {
        if let masterVolume = scalarProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: direction.scope,
            element: kAudioObjectPropertyElementMain
        ) {
            return Double(masterVolume)
        }

        let channelVolumes = [UInt32(1), UInt32(2)].compactMap { channel in
            scalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: direction.scope,
                element: channel
            )
        }

        guard !channelVolumes.isEmpty else {
            return nil
        }

        let total = channelVolumes.reduce(Float32(0), +)
        return Double(total / Float32(channelVolumes.count))
    }

    func setVolume(_ volume: Double, for deviceID: AudioObjectID, direction: AudioDeviceDirection) {
        let clampedVolume = Float32(max(0, min(1, volume)))

        if setScalarProperty(
            clampedVolume,
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: direction.scope,
            element: kAudioObjectPropertyElementMain
        ) {
            return
        }

        for channel in [UInt32(1), UInt32(2)] {
            _ = setScalarProperty(
                clampedVolume,
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: direction.scope,
                element: channel
            )
        }
    }

    func runningOutputApps(storedVolume: (String) -> Double) -> [AudioApp] {
        struct RunningAudioApp {
            let ownerPID: pid_t
            let bundleID: String
            let name: String
            let icon: NSImage?
            var audioObjectIDs: [AudioObjectID]
        }

        var groupedApps: [String: RunningAudioApp] = [:]

        for processID in audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        ) {
            guard boolProperty(processID, selector: kAudioProcessPropertyIsRunningOutput),
                  let pid = pidProperty(processID),
                  pid != ProcessInfo.processInfo.processIdentifier else {
                continue
            }

            let audioBundleID = stringProperty(processID, selector: kAudioProcessPropertyBundleID)
            guard let responsibleApp = responsibleApplication(
                for: pid,
                audioBundleID: audioBundleID
            ) else {
                continue
            }

            let bundleID = responsibleApp.bundleIdentifier
                ?? audioBundleID
                ?? "pid.\(responsibleApp.processIdentifier)"
            let appName = responsibleApp.localizedName ?? bundleID
            let icon = responsibleApp.icon
            let storageKey = bundleID.isEmpty ? "pid.\(responsibleApp.processIdentifier)" : bundleID
            let groupingKey = storageKey.isEmpty ? "pid.\(pid)" : storageKey

            if groupedApps[groupingKey] == nil {
                groupedApps[groupingKey] = RunningAudioApp(
                    ownerPID: responsibleApp.processIdentifier,
                    bundleID: storageKey,
                    name: appName,
                    icon: icon,
                    audioObjectIDs: []
                )
            }

            groupedApps[groupingKey]?.audioObjectIDs.append(processID)
        }

        return groupedApps.map { appID, app in
            AudioApp(
                id: appID,
                pid: app.ownerPID,
                bundleID: app.bundleID,
                name: app.name,
                audioObjectIDs: app.audioObjectIDs.sorted(),
                icon: app.icon,
                volume: storedVolume(app.bundleID)
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func setSystemDevice(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) {
        var address = propertyAddress(selector: selector)
        var mutableDeviceID = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &mutableDeviceID
        )
    }

    private func hasStreams(deviceID: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreams,
            scope: direction.scope
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func isHidden(_ deviceID: AudioObjectID) -> Bool {
        var address = propertyAddress(selector: kAudioDevicePropertyIsHidden)
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    private func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = propertyAddress(selector: selector, scope: scope)
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }

        var objectIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &objectIDs)
        return status == noErr ? objectIDs.filter { $0 != kAudioObjectUnknown } : []
    }

    private func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector: selector)
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }

        guard status == noErr else {
            return nil
        }

        return value as String?
    }

    private func pidProperty(_ objectID: AudioObjectID) -> pid_t? {
        var address = propertyAddress(selector: kAudioProcessPropertyPID)
        var pid = pid_t(0)
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &pid)
        return status == noErr && pid > 0 ? pid : nil
    }

    private func boolProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = propertyAddress(selector: selector)
        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    private func responsibleApplication(
        for pid: pid_t,
        audioBundleID: String?
    ) -> NSRunningApplication? {
        var visited = Set<pid_t>()
        var currentPID = pid

        while currentPID > 0, !visited.contains(currentPID) {
            visited.insert(currentPID)

            if currentPID != ProcessInfo.processInfo.processIdentifier,
               let app = NSRunningApplication(processIdentifier: currentPID),
               app.activationPolicy == .regular {
                return app
            }

            guard let parentPID = parentProcessID(for: currentPID),
                  parentPID != currentPID else {
                break
            }

            currentPID = parentPID
        }

        return inferredHostApplication(
            for: pid,
            audioBundleID: audioBundleID
        )
    }

    private func inferredHostApplication(
        for pid: pid_t,
        audioBundleID: String?
    ) -> NSRunningApplication? {
        let processName = processName(for: pid) ?? ""
        let processPath = processPath(for: pid) ?? ""
        let searchableText = [
            audioBundleID,
            processName,
            processPath,
        ]
        .compactMap(\.self)
        .joined(separator: " ")
        .lowercased()

        if searchableText.contains("com.apple.safari")
            || searchableText.contains("safari.app")
            || searchableText.contains("safari web content") {
            return runningApplication(bundleIdentifiers: [
                "com.apple.Safari",
                "com.apple.SafariTechnologyPreview",
            ])
        }

        if searchableText.contains("com.apple.webkit")
            || searchableText.contains("webkit.webcontent")
            || searchableText.contains("web content") {
            return runningApplication(bundleIdentifiers: [
                "com.apple.Safari",
                "com.apple.SafariTechnologyPreview",
            ])
        }

        return nil
    }

    private func runningApplication(bundleIdentifiers: [String]) -> NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular
            }) {
                return app
            }
        }

        return nil
    }

    private func processName(for pid: pid_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))

        guard length > 0 else {
            return nil
        }

        return String(cString: nameBuffer)
    }

    private func processPath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        guard length > 0 else {
            return nil
        }

        return String(cString: pathBuffer)
    }

    private func parentProcessID(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))

        guard result == Int32(size), info.pbi_ppid > 0 else {
            return nil
        }

        return pid_t(info.pbi_ppid)
    }

    private func uint32Property(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = propertyAddress(selector: selector)
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func scalarProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func setScalarProperty(
        _ value: Float32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else {
            return false
        }

        var mutableValue = value
        let status = AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        )
        return status == noErr
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func iconName(for identity: AudioDeviceIdentity, direction: AudioDeviceDirection) -> String {
        guard direction == .output else {
            return "mic.fill"
        }

        let searchableText = identity.searchableText

        if isBuiltInSpeaker(identity) {
            return "macbook"
        }

        if let beatsIcon = beatsIconName(for: searchableText) {
            return beatsIcon
        }

        if let appleIcon = appleAudioIconName(for: searchableText, identity: identity) {
            return appleIcon
        }

        if searchableText.containsAny(["display", "显示器", "monitor"]) {
            return "display"
        }

        if searchableText.containsAny(["airplay"]) || identity.transportType == kAudioDeviceTransportTypeAirPlay {
            return "airplayaudio"
        }

        return "headphones"
    }

    private func isBuiltInSpeaker(_ identity: AudioDeviceIdentity) -> Bool {
        guard identity.transportType == kAudioDeviceTransportTypeBuiltIn else {
            return false
        }

        return identity.searchableText.containsAny([
            "macbook",
            "built-in",
            "internal",
            "speaker",
            "扬声器"
        ])
    }

    private func appleAudioIconName(
        for searchableText: String,
        identity: AudioDeviceIdentity
    ) -> String? {
        if searchableText.containsAny(["airpods max", "airpodsmax"]) {
            return "airpods.max"
        }

        if searchableText.contains("airpods pro") || searchableText.contains("airpodspro") {
            if searchableText.containsAny(["gen 1", "gen1", "1st gen", "1st generation", "generation 1", "第一代", "一代"]) {
                return "airpods.pro.gen1"
            }

            if searchableText.containsAny(["gen 3", "gen3", "3rd gen", "3rd generation", "generation 3", "第三代", "三代"]) {
                return "airpods.pro.gen3"
            }

            return "airpods.pro"
        }

        if searchableText.contains("airpods") {
            if searchableText.containsAny(["gen 4", "gen4", "4th gen", "4th generation", "generation 4", "第四代", "四代"]) {
                return "airpods.gen4"
            }

            if searchableText.containsAny(["gen 3", "gen3", "3rd gen", "3rd generation", "generation 3", "第三代", "三代"]) {
                return "airpods.gen3"
            }

            return "airpods"
        }

        if searchableText.containsAny(["homepod mini", "homepodmini"]) {
            return "homepod.mini"
        }

        if searchableText.contains("homepod") {
            return "homepod"
        }

        if searchableText.containsAny(["apple tv", "appletv"]) {
            return "appletv"
        }

        if identity.manufacturerText.contains("apple") && searchableText.containsAny(["iphone", "ipad"]) {
            return searchableText.contains("ipad") ? "ipad" : "iphone"
        }

        return nil
    }

    private func beatsIconName(for searchableText: String) -> String? {
        guard searchableText.contains("beats") else {
            return nil
        }

        if searchableText.containsAny(["beats pill", "beatspill"]) {
            return "beats.pill"
        }

        if searchableText.containsAny(["solo buds", "solobuds"]) {
            return "beats.solobuds"
        }

        if searchableText.containsAny(["studio buds plus", "studio buds +", "studiobudsplus"]) {
            return "beats.studiobuds.plus"
        }

        if searchableText.containsAny(["studio buds", "studiobuds"]) {
            return "beats.studiobuds"
        }

        if searchableText.containsAny(["fit pro", "fitpro"]) {
            return "beats.fitpro"
        }

        if searchableText.containsAny(["powerbeats pro 2", "powerbeatspro2", "powerbeats pro 2nd", "powerbeats pro second"]) {
            return "beats.powerbeats.pro.2"
        }

        if searchableText.containsAny(["powerbeats pro", "powerbeatspro"]) {
            return "beats.powerbeats.pro"
        }

        if searchableText.containsAny(["powerbeats3", "powerbeats 3"]) {
            return "beats.powerbeats3"
        }

        if searchableText.contains("powerbeats") {
            return "beats.powerbeats"
        }

        if searchableText.containsAny(["beatsx", "beats x", "flex", "urbeats"]) {
            return "beats.earphones"
        }

        return "beats.headphones"
    }
}

nonisolated final class CoreAudioVolumeObserver {
    private let queue = DispatchQueue(label: "MacMix.CoreAudioVolumeObserver")
    private var outputDeviceID: AudioObjectID?
    private var isObservingSystemDefault = false
    private var observedVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isObservingSystemDefault else {
            return
        }

        isObservingSystemDefault = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindOutputDevice()
            self?.notifyChange()
        }
        defaultDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )

        rebindOutputDevice()
    }

    func stop() {
        removeOutputDeviceListeners()

        if isObservingSystemDefault {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if let defaultDeviceListener {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    queue,
                    defaultDeviceListener
                )
            }
            defaultDeviceListener = nil
            isObservingSystemDefault = false
        }
    }

    private func rebindOutputDevice() {
        let nextDeviceID = currentDefaultOutputDeviceID()
        guard outputDeviceID != nextDeviceID else {
            return
        }

        removeOutputDeviceListeners()
        outputDeviceID = nextDeviceID

        guard let nextDeviceID else {
            return
        }

        observedVolumeAddresses = volumeAddresses(for: nextDeviceID)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyChange()
        }
        volumeListener = listener

        for address in observedVolumeAddresses {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                nextDeviceID,
                &mutableAddress,
                queue,
                listener
            )
        }
    }

    private func currentDefaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func removeOutputDeviceListeners() {
        guard let outputDeviceID else {
            observedVolumeAddresses.removeAll()
            return
        }

        if let volumeListener {
            for address in observedVolumeAddresses {
                var mutableAddress = address
                AudioObjectRemovePropertyListenerBlock(
                    outputDeviceID,
                    &mutableAddress,
                    queue,
                    volumeListener
                )
            }
        }

        observedVolumeAddresses.removeAll()
        volumeListener = nil
        self.outputDeviceID = nil
    }

    private func volumeAddresses(for deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let elements = [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2),
        ]

        let selectors: [AudioObjectPropertySelector] = [
            kAudioDevicePropertyVolumeScalar,
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        ]

        return selectors.flatMap { selector in
            elements.compactMap { element in
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )

                return AudioObjectHasProperty(deviceID, &address) ? address : nil
            }
        }
    }

    private func notifyChange() {
        Task { @MainActor in
            onChange()
        }
    }
}

private struct AudioDeviceIdentity {
    let name: String
    let manufacturer: String?
    let modelUID: String?
    let deviceUID: String?
    let transportType: UInt32?

    var searchableText: String {
        [name, manufacturer, modelUID, deviceUID]
            .compactMap(\.self)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var manufacturerText: String {
        (manufacturer ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var isMacMixInternalMixer: Bool {
        searchableText.containsAny(["macmix mixer", "macmix音乐"])
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
