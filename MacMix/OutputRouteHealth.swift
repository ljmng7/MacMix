import CoreAudio
import Foundation
import Atomics

// No activity/content heuristic: silence and paused playback are valid states.
nonisolated struct OutputRecoveryBudget {
    private(set) var key = ""
    private(set) var failures = 0
    private var stableAt: TimeInterval = 0
    private var retryAt: TimeInterval = 0

    mutating func observe(_ key: String, now: TimeInterval, waitForStability: Bool = true) {
        guard self.key != key else { return }
        self.key = key
        failures = 0
        stableAt = waitForStability ? now + 0.3 : now
        retryAt = now
    }
    func canAttempt(ready: Bool, now: TimeInterval) -> Bool {
        ready && now >= stableAt && failures < 4 && now >= retryAt
    }
    mutating func failed(now: TimeInterval) {
        failures += 1
        retryAt = now + min(8, pow(2, Double(failures - 1)))
    }
}

// Flat EQ at unity following the system sounds the same as native output, so
// its warm graph is only kept while the app plays. A paused app never holds a
// tap across device changes such as headphones being taken off.
nonisolated enum WarmGraphPolicy {
    static let idleRelease: TimeInterval = 10

    static func admits(soundNeutral: Bool, metering: Bool, hasMember: Bool,
                       outputting: Bool, lastOutputAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard soundNeutral, !metering, !outputting else { return true }
        guard hasMember, let lastOutputAt else { return false }
        return now - lastOutputAt < idleRelease
    }
}

// The tap mutes the app's native output, so a graph that silently stops
// rendering while its app plays leaves that app silent. Only that combination
// counts: paused apps and unavailable devices never trigger a rebuild.
nonisolated struct OutputStallDetector {
    static let minimumOutputDuration: TimeInterval = 2
    static let minimumStallDuration: TimeInterval = 2

    private(set) var graph: AudioObjectID?
    private var frames: UInt64 = 0
    private var lastAdvanceAt: TimeInterval = 0
    private var outputtingSince: TimeInterval?
    private var subdevicesMissingSince: TimeInterval?

    func stalledFor(now: TimeInterval) -> TimeInterval { now - lastAdvanceAt }

    /// `subdevicesActive` is nil when HAL cannot answer; that is never a failure.
    mutating func observe(graph: AudioObjectID, frames: UInt64, outputting: Bool, deviceReady: Bool,
                          subdevicesActive: Bool?, now: TimeInterval) -> String? {
        if self.graph != graph {
            self = Self()
            self.graph = graph
            self.frames = frames
            lastAdvanceAt = now
        }
        if frames != self.frames {
            self.frames = frames
            lastAdvanceAt = now
        }
        guard outputting, deviceReady else {
            outputtingSince = nil
            subdevicesMissingSince = nil
            return nil
        }
        let since = outputtingSince ?? now
        outputtingSince = since
        subdevicesMissingSince = subdevicesActive == false ? (subdevicesMissingSince ?? now) : nil
        guard now - since >= Self.minimumOutputDuration else { return nil }
        if now - lastAdvanceAt >= Self.minimumStallDuration { return "callback_stalled" }
        if let missing = subdevicesMissingSince, now - missing >= Self.minimumStallDuration { return "subdevice_inactive" }
        return nil
    }
}

// Wearing headphones again usually produces no HAL event, so stall recovery
// uses a rolling window instead of a budget that can be exhausted for good.
nonisolated struct OutputStallLimiter {
    static let window: TimeInterval = 30
    static let maximumAttempts = 3

    private(set) var attempts: [TimeInterval] = []
    private(set) var holdUntil: TimeInterval = 0
    private var consecutiveFailures = 0

    func isHolding(now: TimeInterval) -> Bool { now < holdUntil }

    func canRebuild(now: TimeInterval) -> Bool {
        !isHolding(now: now) && attempts.filter { now - $0 < Self.window }.count < Self.maximumAttempts
    }

    mutating func began(now: TimeInterval) {
        attempts = attempts.filter { now - $0 < Self.window } + [now]
    }

    mutating func succeeded() {
        consecutiveFailures = 0
        holdUntil = 0
    }

    mutating func failed(now: TimeInterval) {
        consecutiveFailures += 1
        holdUntil = max(holdUntil, now + min(8, pow(2, Double(consecutiveFailures - 1))))
    }

    /// Hold until the oldest attempt leaves the window; never give up permanently.
    mutating func exhaust(now: TimeInterval) {
        let recent = attempts.filter { now - $0 < Self.window }
        holdUntil = max(holdUntil, (recent.min() ?? now) + Self.window)
    }
}

nonisolated struct OutputRouteHealth: Equatable {
    let signature: String
    let ready: Bool
    let objects: [AudioObjectID]
    var deviceSignatures: [String: String] = [:]
    var deviceIDs: [AudioObjectID] = []
    var readyDeviceUIDs: Set<String> = []
    var objectsByDeviceUID: [String: [AudioObjectID]] = [:]

    static func read(uids: [String]) -> Self {
        guard let devices = readHALAudioObjectIDs(objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices) else {
            return Self(signature: "devices-unreadable", ready: false, objects: [])
        }
        var parts: [String] = []
        var objects: [AudioObjectID] = []
        var deviceIDs: [AudioObjectID] = []
        var ready = true
        var deviceSignatures: [String: String] = [:]
        var readyDeviceUIDs = Set<String>()
        var objectsByDeviceUID: [String: [AudioObjectID]] = [:]
        for uid in Set(uids).sorted() {
            let start = parts.count
            let firstObject = objects.count
            defer {
                deviceSignatures[uid] = parts[start...].joined(separator: "|")
                objectsByDeviceUID[uid] = Array(objects[firstObject...])
            }
            let device = devices.first { deviceUID($0) == uid }
            guard let device else { parts.append("\(uid):missing"); ready = false; continue }
            objects.append(device)
            deviceIDs.append(device)
            let alive = uintProperty(device, kAudioDevicePropertyDeviceIsAlive) == 1
            parts.append("\(uid):\(device):alive=\(alive)")
            guard let streams = readHALAudioObjectIDs(objectID: device, selector: kAudioDevicePropertyStreams,
                scope: kAudioDevicePropertyScopeOutput), !streams.isEmpty else {
                parts.append("no-streams"); ready = false; continue
            }
            var hasUsableStream = false
            var formatsReadable = true
            for stream in streams {
                objects.append(stream)
                var address = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var format = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr else {
                    parts.append("\(stream):unreadable"); formatsReadable = false; continue
                }
                let active = uintProperty(stream, kAudioStreamPropertyIsActive) == 1
                hasUsableStream = hasUsableStream || (active && format.mSampleRate > 0 && format.mChannelsPerFrame > 0)
                parts.append("\(stream):\(active):\(format.mSampleRate):\(format.mFormatID):\(format.mFormatFlags):\(format.mBytesPerPacket):\(format.mFramesPerPacket):\(format.mBytesPerFrame):\(format.mChannelsPerFrame):\(format.mBitsPerChannel)")
            }
            let deviceReady = alive && hasUsableStream && formatsReadable
            if deviceReady { readyDeviceUIDs.insert(uid) }
            ready = ready && deviceReady
        }
        return Self(signature: parts.joined(separator: "|"), ready: ready, objects: objects, deviceSignatures: deviceSignatures, deviceIDs: deviceIDs, readyDeviceUIDs: readyDeviceUIDs, objectsByDeviceUID: objectsByDeviceUID)
    }

    /// Project one shared HAL read onto the devices needed by an app member.
    func selecting(_ uids: [String]) -> Self {
        let selected = Set(uids).sorted()
        let signatures = Dictionary(uniqueKeysWithValues: selected.map {
            ($0, deviceSignatures[$0] ?? "missing")
        })
        return Self(signature: selected.map { signatures[$0]! }.joined(separator: "|"),
            ready: selected.allSatisfy { readyDeviceUIDs.contains($0) },
            objects: selected.flatMap { objectsByDeviceUID[$0] ?? [] },
            deviceSignatures: signatures,
            deviceIDs: selected.compactMap { objectsByDeviceUID[$0]?.first },
            readyDeviceUIDs: readyDeviceUIDs.intersection(selected),
            objectsByDeviceUID: objectsByDeviceUID.filter { selected.contains($0.key) })
    }

    static func uintProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func deviceUID(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String? : nil
    }
}

// Property notifications latch transient failures even when the next poll sees
// exactly the same UID/format again. These are HAL listeners, never audio IO.
nonisolated final class OutputRouteHealthMonitor {
    let revision = ManagedAtomic<UInt64>(0)
    private let queue = DispatchQueue(label: "MacMix.OutputHealthNotifications")
    private var registrations: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(objects: [AudioObjectID], selectors: [AudioObjectPropertySelector] = [
        kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyStreams,
        kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyIOStoppedAbnormally,
        kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat,
        kAudioStreamPropertyIsActive
    ]) {
        for object in objects {
            for selector in selectors {
                var address = AudioObjectPropertyAddress(mSelector: selector,
                    mScope: selector == kAudioDevicePropertyStreams ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                guard AudioObjectHasProperty(object, &address) else { continue }
                let counter = revision
                let listener: AudioObjectPropertyListenerBlock = { _, _ in
                    counter.wrappingIncrement(ordering: .relaxed)
                }
                if AudioObjectAddPropertyListenerBlock(object, &address, queue, listener) == noErr {
                    registrations.append((object, address, listener))
                }
            }
        }
    }
    deinit {
        for (object, var address, listener) in registrations {
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
        }
    }
}
