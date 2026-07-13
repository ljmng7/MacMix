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

nonisolated enum DefaultAudioDeviceUIDRead: Sendable, Equatable {
    case device(String)
    case noDevice
    case failed
}

struct CoreAudioHardware {
    func devices(for direction: AudioDeviceDirection) -> [AudioDevice] {
        let defaultID = defaultDeviceID(for: direction)

        return audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )
        .filter {
            hasStreams(deviceID: $0, direction: direction)
                && canBeDefaultDevice($0, direction: direction)
        }
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
    }

    private func canBeDefaultDevice(
        _ deviceID: AudioObjectID,
        direction: AudioDeviceDirection
    ) -> Bool {
        let device = AudioHardwareDevice(id: deviceID)

        switch direction {
        case .input:
            return (try? device.canBeDefaultInputDevice) == true
        case .output:
            return (try? device.canBeDefaultOutputDevice) == true
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

        let channelVolumes = audioVolumeChannelElements(deviceID: deviceID, direction: direction).compactMap { channel in
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

    func isMuted(for deviceID: AudioObjectID, direction: AudioDeviceDirection) -> Bool? {
        if let masterMute = uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: direction.scope,
            element: kAudioObjectPropertyElementMain
        ) {
            return masterMute != 0
        }

        let channelMutes = audioVolumeChannelElements(
            deviceID: deviceID,
            direction: direction
        ).compactMap { channel in
            uint32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: direction.scope,
                element: channel
            )
        }

        guard !channelMutes.isEmpty else {
            return nil
        }

        return channelMutes.allSatisfy { $0 != 0 }
    }

    @discardableResult
    func setVolume(_ volume: Double, for deviceID: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        let clampedVolume = Float32(max(0, min(1, volume)))

        if setScalarProperty(
            clampedVolume,
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: direction.scope,
            element: kAudioObjectPropertyElementMain
        ) {
            return true
        }

        var didSetVolume = false
        for channel in audioVolumeChannelElements(deviceID: deviceID, direction: direction) {
            if setScalarProperty(
                clampedVolume,
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: direction.scope,
                element: channel
            ) {
                didSetVolume = true
            }
        }

        return didSetVolume
    }

    @discardableResult
    func setMuted(_ isMuted: Bool, for deviceID: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        let muteValue: UInt32 = isMuted ? 1 : 0

        if setUInt32Property(
            muteValue,
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: direction.scope,
            element: kAudioObjectPropertyElementMain
        ) {
            return true
        }

        var didSetMute = false
        for channel in audioVolumeChannelElements(deviceID: deviceID, direction: direction) {
            if setUInt32Property(
                muteValue,
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: direction.scope,
                element: channel
            ) {
                didSetMute = true
            }
        }

        return didSetMute
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
            // Keep audio clients visible as soon as they register with HAL instead of
            // waiting until their first buffers are already playing. That also lets the
            // mixer prepare from the process object before a long unity-gain window.
            guard let pid = pidProperty(processID),
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

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
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

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
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

    private func setUInt32Property(
        _ value: UInt32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }

        var mutableValue = value
        let status = AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
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

nonisolated final class DefaultOutputRouteProbe: @unchecked Sendable {
    private let queryQueue = DispatchQueue(
        label: "MacMix.DefaultOutputRouteProbe",
        qos: .userInitiated
    )
    private let timeoutQueue = DispatchQueue(label: "MacMix.DefaultOutputRouteProbe.Timeout")
    private let stateLock = NSLock()
    private var isQueryInFlight = false

    func read(timeout: TimeInterval = 0.15) async -> DefaultAudioDeviceUIDRead {
        guard beginQuery() else {
            return .failed
        }

        return await withCheckedContinuation { continuation in
            let gate = DefaultOutputRouteProbeGate(continuation: continuation)
            queryQueue.async { [self] in
                defer { endQuery() }
                gate.resume(with: readDefaultAudioDeviceUID(for: .output))
            }
            timeoutQueue.asyncAfter(deadline: .now() + timeout) {
                gate.resume(with: .failed)
            }
        }
    }

    private func beginQuery() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isQueryInFlight else {
            return false
        }

        isQueryInFlight = true
        return true
    }

    private func endQuery() {
        stateLock.lock()
        isQueryInFlight = false
        stateLock.unlock()
    }
}

nonisolated final class DefaultOutputDeviceWriter: @unchecked Sendable {
    private struct Request {
        let generation: UInt64
        let deviceID: AudioObjectID
    }

    private struct PendingCompletion {
        let generation: UInt64
        let handler: @Sendable (Bool) -> Void
    }

    private let queue = DispatchQueue(
        label: "MacMix.DefaultOutputDeviceWriter",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var nextGeneration: UInt64 = 0
    private var latestRequest: Request?
    private var pendingCompletions: [PendingCompletion] = []
    private var isWorkerRunning = false

    func select(
        _ deviceID: AudioObjectID,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let shouldStartWorker: Bool

        stateLock.lock()
        nextGeneration &+= 1
        let generation = nextGeneration
        latestRequest = Request(
            generation: generation,
            deviceID: deviceID
        )
        pendingCompletions.append(
            PendingCompletion(generation: generation, handler: completion)
        )
        shouldStartWorker = startWorkerIfNeededLocked()
        stateLock.unlock()

        if shouldStartWorker {
            queue.async { [self] in
                applyLatestIntent()
            }
        }
    }

    private func applyLatestIntent() {
        while true {
            let request: Request

            stateLock.lock()
            guard let latestRequest else {
                let completions = finishWorkerLocked()
                stateLock.unlock()
                complete(completions, finalGeneration: nil, succeeded: false)
                return
            }
            request = latestRequest
            stateLock.unlock()

            let didApply = setDefaultOutputDevice(request.deviceID)

            stateLock.lock()
            guard self.latestRequest?.generation == request.generation else {
                stateLock.unlock()
                continue
            }

            let completions = finishWorkerLocked()
            stateLock.unlock()
            complete(
                completions,
                finalGeneration: request.generation,
                succeeded: didApply
            )
            return
        }
    }

    private func startWorkerIfNeededLocked() -> Bool {
        guard !isWorkerRunning else {
            return false
        }

        isWorkerRunning = true
        return true
    }

    private func finishWorkerLocked() -> [PendingCompletion] {
        isWorkerRunning = false
        let completions = pendingCompletions
        pendingCompletions.removeAll(keepingCapacity: true)
        return completions
    }

    private func complete(
        _ completions: [PendingCompletion],
        finalGeneration: UInt64?,
        succeeded: Bool
    ) {
        for completion in completions {
            completion.handler(
                succeeded && completion.generation == finalGeneration
            )
        }
    }
}

nonisolated private final class DefaultOutputRouteProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<DefaultAudioDeviceUIDRead, Never>

    init(continuation: CheckedContinuation<DefaultAudioDeviceUIDRead, Never>) {
        self.continuation = continuation
    }

    func resume(with result: DefaultAudioDeviceUIDRead) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(returning: result)
    }
}

nonisolated private func readDefaultAudioDeviceUID(
    for direction: AudioDeviceDirection
) -> DefaultAudioDeviceUIDRead {
    var address = AudioObjectPropertyAddress(
        mSelector: direction.defaultDeviceSelector,
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

    guard status == noErr else {
        return .failed
    }

    guard deviceID != kAudioObjectUnknown else {
        return .noDevice
    }

    address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: CFString?
    dataSize = UInt32(MemoryLayout<CFString?>.size)
    let uidStatus = withUnsafeMutablePointer(to: &uid) { pointer in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
    }

    guard uidStatus == noErr, let uid else {
        return .failed
    }

    return .device(uid as String)
}

nonisolated private func setDefaultOutputDevice(_ deviceID: AudioObjectID) -> Bool {
    let device = AudioHardwareDevice(id: deviceID)
    do {
        guard try device.canBeDefaultOutputDevice else {
            return false
        }
    } catch {
        return false
    }

    // A manual selection in macOS updates both regular output and the sound-effects
    // output. Writing only dOut leaves Bluetooth Smart Routing's transient sOut intent
    // alive, which can immediately pull dOut back to the in-ear device.
    for _ in 0..<2 {
        do {
            try AudioHardwareSystem.shared.setDefaultOutputDevice(device)
            try AudioHardwareSystem.shared.setDefaultSoundEffectsDevice(device)
        } catch {
            continue
        }

        var stableReads = 0
        for _ in 0..<8 {
            if defaultAudioDeviceID(
                selector: kAudioHardwarePropertyDefaultOutputDevice
            ) == deviceID {
                stableReads += 1
                if stableReads >= 3 {
                    return true
                }
            } else {
                stableReads = 0
            }

            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    return false
}

nonisolated private func defaultAudioDeviceID(
    selector: AudioObjectPropertySelector
) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
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

nonisolated private func audioVolumeChannelElements(
    deviceID: AudioObjectID,
    direction: AudioDeviceDirection
) -> [AudioObjectPropertyElement] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: direction.scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
          dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
        return [1, 2]
    }

    let storage = UnsafeMutableRawPointer.allocate(
        byteCount: Int(dataSize),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { storage.deallocate() }

    let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else {
        return [1, 2]
    }

    let channelCount = UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { count, buffer in
        count + Int(buffer.mNumberChannels)
    }

    guard channelCount > 0 else {
        return [1, 2]
    }

    return (1...channelCount).map(AudioObjectPropertyElement.init)
}

nonisolated final class CoreAudioDeviceObserver {
    private let queue = DispatchQueue(label: "MacMix.CoreAudioDeviceObserver")
    private var outputDeviceID: AudioObjectID?
    private var inputDeviceID: AudioObjectID?
    private var isObservingSystem = false
    private var outputVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var inputVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var defaultInputDeviceListener: AudioObjectPropertyListenerBlock?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processOutputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var outputVolumeListener: AudioObjectPropertyListenerBlock?
    private var inputVolumeListener: AudioObjectPropertyListenerBlock?
    private let onOutputChange: @MainActor () -> Void
    private let onInputChange: @MainActor () -> Void
    private let onOutputAppsChange: @MainActor () -> Void

    init(
        onOutputChange: @escaping @MainActor () -> Void,
        onInputChange: @escaping @MainActor () -> Void,
        onOutputAppsChange: @escaping @MainActor () -> Void
    ) {
        self.onOutputChange = onOutputChange
        self.onInputChange = onInputChange
        self.onOutputAppsChange = onOutputAppsChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isObservingSystem else {
            return
        }

        isObservingSystem = true

        let deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindDevice(for: .output)
            self?.rebindDevice(for: .input)
            self?.notifyChange(for: .output)
            self?.notifyChange(for: .input)
        }
        self.deviceListListener = deviceListListener
        addSystemListener(selector: kAudioHardwarePropertyDevices, listener: deviceListListener)

        let defaultOutputDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindDevice(for: .output)
            self?.notifyChange(for: .output)
        }
        self.defaultOutputDeviceListener = defaultOutputDeviceListener
        addSystemListener(selector: kAudioHardwarePropertyDefaultOutputDevice, listener: defaultOutputDeviceListener)

        let defaultInputDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindDevice(for: .input)
            self?.notifyChange(for: .input)
        }
        self.defaultInputDeviceListener = defaultInputDeviceListener
        addSystemListener(selector: kAudioHardwarePropertyDefaultInputDevice, listener: defaultInputDeviceListener)

        let processListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindProcessOutputListeners()
            self?.notifyOutputAppsChange()
        }
        self.processListListener = processListListener
        addSystemListener(
            selector: kAudioHardwarePropertyProcessObjectList,
            listener: processListListener
        )

        rebindDevice(for: .output)
        rebindDevice(for: .input)
        rebindProcessOutputListeners()
    }

    func stop() {
        removeDeviceListeners(for: .output)
        removeDeviceListeners(for: .input)
        removeProcessOutputListeners()

        if isObservingSystem {
            removeSystemListener(selector: kAudioHardwarePropertyDevices, listener: deviceListListener)
            removeSystemListener(selector: kAudioHardwarePropertyDefaultOutputDevice, listener: defaultOutputDeviceListener)
            removeSystemListener(selector: kAudioHardwarePropertyDefaultInputDevice, listener: defaultInputDeviceListener)
            removeSystemListener(
                selector: kAudioHardwarePropertyProcessObjectList,
                listener: processListListener
            )
            deviceListListener = nil
            defaultOutputDeviceListener = nil
            defaultInputDeviceListener = nil
            processListListener = nil
            isObservingSystem = false
        }

    }

    private func rebindDevice(for direction: AudioDeviceDirection) {
        let nextDeviceID = currentDefaultDeviceID(for: direction)
        guard deviceID(for: direction) != nextDeviceID else {
            return
        }

        removeDeviceListeners(for: direction)
        setDeviceID(nextDeviceID, for: direction)

        guard let nextDeviceID else {
            return
        }

        let addresses = volumeAddresses(for: nextDeviceID, direction: direction)
        setVolumeAddresses(addresses, for: direction)

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyChange(for: direction)
        }
        setVolumeListener(listener, for: direction)

        addDeviceListeners(addresses, deviceID: nextDeviceID, listener: listener)
    }

    private func currentDefaultDeviceID(for direction: AudioDeviceDirection) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
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

    private func addSystemListener(
        selector: AudioObjectPropertySelector,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = systemAddress(selector: selector)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
    }

    private func removeSystemListener(
        selector: AudioObjectPropertySelector,
        listener: AudioObjectPropertyListenerBlock?
    ) {
        guard let listener else {
            return
        }

        var address = systemAddress(selector: selector)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
    }

    private func addDeviceListeners(
        _ addresses: [AudioObjectPropertyAddress],
        deviceID: AudioObjectID,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) {
        for address in addresses {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &mutableAddress,
                queue,
                listener
            )
        }
    }

    private func removeDeviceListeners(for direction: AudioDeviceDirection) {
        guard let deviceID = deviceID(for: direction) else {
            setVolumeAddresses([], for: direction)
            setVolumeListener(nil, for: direction)
            return
        }

        if let listener = volumeListener(for: direction) {
            for address in volumeAddresses(for: direction) {
                var mutableAddress = address
                AudioObjectRemovePropertyListenerBlock(
                    deviceID,
                    &mutableAddress,
                    queue,
                    listener
                )
            }
        }

        setVolumeAddresses([], for: direction)
        setVolumeListener(nil, for: direction)
        setDeviceID(nil, for: direction)
    }

    private func rebindProcessOutputListeners() {
        removeProcessOutputListeners()

        for processID in systemAudioObjectIDs(
            selector: kAudioHardwarePropertyProcessObjectList
        ) {
            var address = systemAddress(
                selector: kAudioProcessPropertyIsRunningOutput
            )
            guard AudioObjectHasProperty(processID, &address) else {
                continue
            }

            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.notifyOutputAppsChange()
            }
            let status = AudioObjectAddPropertyListenerBlock(
                processID,
                &address,
                queue,
                listener
            )
            if status == noErr {
                processOutputListeners[processID] = listener
            }
        }
    }

    private func removeProcessOutputListeners() {
        for (processID, listener) in processOutputListeners {
            var address = systemAddress(
                selector: kAudioProcessPropertyIsRunningOutput
            )
            AudioObjectRemovePropertyListenerBlock(
                processID,
                &address,
                queue,
                listener
            )
        }
        processOutputListeners.removeAll()
    }

    private func systemAudioObjectIDs(
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = systemAddress(selector: selector)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }

        var objectIDs = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: count
        )
        guard AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        ) == noErr else {
            return []
        }

        return objectIDs.filter { $0 != kAudioObjectUnknown }
    }

    private func volumeAddresses(for deviceID: AudioObjectID, direction: AudioDeviceDirection) -> [AudioObjectPropertyAddress] {
        let elements = [kAudioObjectPropertyElementMain]
            + audioVolumeChannelElements(deviceID: deviceID, direction: direction)

        let selectors: [AudioObjectPropertySelector] = [
            kAudioDevicePropertyVolumeScalar,
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyMute,
        ]

        return selectors.flatMap { selector in
            elements.compactMap { element in
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: direction.scope,
                    mElement: element
                )

                return AudioObjectHasProperty(deviceID, &address) ? address : nil
            }
        }
    }

    private func deviceID(for direction: AudioDeviceDirection) -> AudioObjectID? {
        switch direction {
        case .input:
            return inputDeviceID
        case .output:
            return outputDeviceID
        }
    }

    private func setDeviceID(_ deviceID: AudioObjectID?, for direction: AudioDeviceDirection) {
        switch direction {
        case .input:
            inputDeviceID = deviceID
        case .output:
            outputDeviceID = deviceID
        }
    }

    private func volumeAddresses(for direction: AudioDeviceDirection) -> [AudioObjectPropertyAddress] {
        switch direction {
        case .input:
            return inputVolumeAddresses
        case .output:
            return outputVolumeAddresses
        }
    }

    private func setVolumeAddresses(_ addresses: [AudioObjectPropertyAddress], for direction: AudioDeviceDirection) {
        switch direction {
        case .input:
            inputVolumeAddresses = addresses
        case .output:
            outputVolumeAddresses = addresses
        }
    }

    private func volumeListener(for direction: AudioDeviceDirection) -> AudioObjectPropertyListenerBlock? {
        switch direction {
        case .input:
            return inputVolumeListener
        case .output:
            return outputVolumeListener
        }
    }

    private func setVolumeListener(_ listener: AudioObjectPropertyListenerBlock?, for direction: AudioDeviceDirection) {
        switch direction {
        case .input:
            inputVolumeListener = listener
        case .output:
            outputVolumeListener = listener
        }
    }

    private func notifyChange(for direction: AudioDeviceDirection) {
        Task { @MainActor in
            switch direction {
            case .input:
                onInputChange()
            case .output:
                onOutputChange()
            }
        }
    }

    private func notifyOutputAppsChange() {
        Task { @MainActor in
            onOutputAppsChange()
        }
    }

    private func systemAddress(selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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
