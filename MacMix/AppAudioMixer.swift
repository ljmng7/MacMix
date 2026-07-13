//
//  AppAudioMixer.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

nonisolated struct AppMixTarget: Sendable, Equatable {
    let id: String
    let audioObjectIDs: [AudioObjectID]
    let volume: Double
}

nonisolated struct AppMixerSnapshot: Sendable, Equatable {
    let routeGeneration: UInt64
    let outputDeviceUID: String?
    let targets: [AppMixTarget]
}

nonisolated struct AppMixerCommand: Sendable {
    let revision: UInt64
    let routeGeneration: UInt64
    let outputDeviceUID: String?
    let targets: [AppMixTarget]

    var snapshot: AppMixerSnapshot {
        AppMixerSnapshot(
            routeGeneration: routeGeneration,
            outputDeviceUID: outputDeviceUID,
            targets: targets
        )
    }
}

nonisolated enum AppMixerResult: Sendable, Equatable {
    case applied
    case failed
    case superseded
}

nonisolated final class AppAudioMixer: @unchecked Sendable {
    static let shared = AppAudioMixer()
    fileprivate static let maximumGain: Float = 2
    private static let maximumGainHandoffDuration: TimeInterval = 0.065
    private static let outputSwitchQuiescenceTimeoutNanoseconds: UInt64 = 3_000_000_000
    private static let outputSwitchQuiescencePollNanoseconds: UInt64 = 20_000_000

    static var isSupported: Bool {
        if #available(macOS 14.4, *) {
            return true
        }

        return false
    }

    // HAL lifecycle calls can block while Core Audio renegotiates a route. MainActor only
    // submits immutable commands and never waits for this queue.
    private let lifecycleQueue = DispatchQueue(
        label: "MacMix.AppAudioMixer.Lifecycle",
        qos: .userInitiated
    )
    private let retirementQueue = DispatchQueue(
        label: "MacMix.AppAudioMixer.Retirement",
        qos: .userInitiated,
        attributes: .concurrent
    )
    // The following mutable state is confined to lifecycleQueue.
    private var engines: [String: any AppGainEngine] = [:]
    private var pendingRetirements: [AppGainEngineRetirement] = []
    private var outputSwitchMuteGuard: ProcessTapMuteGuard?
    private let latestCommandRevision = Atomic<UInt64>(0)

    private init() {}

    func noteLatestCommand(revision: UInt64) {
        latestCommandRevision.store(revision, ordering: .releasing)
    }

    func hasSystemAudioPermission() async -> Bool {
        await probeSystemAudioPermissionOnLifecycleQueue()
    }

    func requestSystemAudioPermissionIfNeeded() async -> Bool {
        await probeSystemAudioPermissionOnLifecycleQueue()
    }

    func requestSystemAudioPermission() async -> Bool {
        await probeSystemAudioPermissionOnLifecycleQueue()
    }

    func submitReconcile(
        _ command: AppMixerCommand,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            completion(reconcile(command))
        }
    }

    func submitTransition(
        _ command: AppMixerCommand,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            completion(transition(command))
        }
    }

    func submitTransitionCompletingOutputSwitch(
        _ command: AppMixerCommand,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            let result = transition(command)
            releaseOutputSwitchMuteGuard()
            completion(result)
        }
    }

    func cancelOutputSwitch(revision: UInt64) {
        lifecycleQueue.async { [self] in
            guard isCurrent(revision: revision) else {
                return
            }
            releaseOutputSwitchMuteGuard()
        }
    }

    /// Releases every process tap, aggregate device, and IOProc before the system
    /// default output is changed. Keeping the old Bluetooth-backed aggregate alive
    /// during the write lets Bluetooth Smart Routing claim the route again.
    func submitQuiesceForOutputSwitch(
        revision: UInt64,
        targets: [AppMixTarget],
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            guard isCurrent(revision: revision) else {
                completion(.superseded)
                return
            }

            releaseOutputSwitchMuteGuard()
            let enginesToRetire = Array(engines.values)
            let guardedAudioObjectIDs = Set(
                enginesToRetire.flatMap(\.tappedObjects)
                    + targets
                        .filter { !isUnity($0.volume) }
                        .flatMap(\.audioObjectIDs)
            )
            if !guardedAudioObjectIDs.isEmpty, #available(macOS 14.4, *) {
                outputSwitchMuteGuard = ProcessTapMuteGuard(
                    audioObjectIDs: guardedAudioObjectIDs.sorted()
                )
            }

            if outputSwitchMuteGuard == nil {
                prepareForUnityHandoff(enginesToRetire)
            }

            guard isCurrent(revision: revision) else {
                completion(.superseded)
                return
            }

            engines.removeAll()
            for engine in enginesToRetire {
                enqueueRetirement(engine)
            }

            let deadline = DispatchTime.now().uptimeNanoseconds
                &+ Self.outputSwitchQuiescenceTimeoutNanoseconds
            pollForOutputSwitchQuiescence(
                revision: revision,
                deadline: deadline,
                completion: completion
            )
        }
    }

    func stopAll() {
        latestCommandRevision.wrappingAdd(1, ordering: .releasing)
        lifecycleQueue.async { [self] in
            stopAllNow()
        }
    }

    private func probeSystemAudioPermissionOnLifecycleQueue() async -> Bool {
        await withCheckedContinuation { continuation in
            lifecycleQueue.async { [self] in
                continuation.resume(returning: probeSystemAudioPermission())
            }
        }
    }

    private func probeSystemAudioPermission() -> Bool {
        guard #available(macOS 14.4, *) else {
            return false
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "MacMix Permission Request"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr, tapID != kAudioObjectUnknown else {
            return false
        }

        AudioHardwareDestroyProcessTap(tapID)
        return true
    }

    private func apply(
        _ target: AppMixTarget,
        command: AppMixerCommand,
        startsAtTargetGain: Bool = false
    ) -> Bool {
        guard isCurrent(command) else {
            return false
        }

        let clampedVolume = Float(max(0, min(Double(Self.maximumGain), target.volume)))

        guard !isUnity(Double(clampedVolume)), let outputDeviceUID = command.outputDeviceUID else {
            guard let engine = engines.removeValue(forKey: target.id) else {
                return true
            }

            prepareForUnityHandoff([engine])
            enqueueRetirement(engine)
            return waitForPendingAggregateRemoval(command: command)
        }

        guard Self.isSupported else {
            return false
        }

        if let engine = engines[target.id] {
            if engine.tappedObjects == target.audioObjectIDs,
               engine.outputDeviceUID == outputDeviceUID {
                guard isCurrent(command) else {
                    return false
                }

                engine.gain = clampedVolume
                return true
            }

            engines.removeValue(forKey: target.id)
            prepareForUnityHandoff([engine])
            enqueueRetirement(engine)
            guard waitForPendingAggregateRemoval(command: command), isCurrent(command) else {
                return false
            }
        }

        guard waitForPendingAggregateRemoval(command: command) else {
            return false
        }

        guard #available(macOS 14.4, *),
              let engine = ProcessTapGainEngine(
                audioObjectIDs: target.audioObjectIDs,
                initialGain: startsAtTargetGain ? clampedVolume : 1,
                gain: clampedVolume,
                outputDeviceUID: outputDeviceUID
              ) else {
            return false
        }

        guard isCurrent(command) else {
            enqueueRetirement(engine)
            _ = waitForPendingAggregateRemoval(command: command)
            return false
        }

        engines[target.id] = engine
        return true
    }

    private func reconcile(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command) else {
            return .superseded
        }

        return reconcileCurrentRoute(command) ? .applied : .failed
    }

    private func transition(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command),
              let outputDeviceUID = command.outputDeviceUID else {
            return .superseded
        }

        let targetByID = Dictionary(uniqueKeysWithValues: command.targets.map { ($0.id, $0) })
        let enginesToReplace = engines.filter { appID, engine in
            guard let target = targetByID[appID] else {
                return true
            }

            return isUnity(target.volume)
                || engine.tappedObjects != target.audioObjectIDs
                || engine.outputDeviceUID != outputDeviceUID
        }

        prepareForUnityHandoff(Array(enginesToReplace.values))

        for (appID, engine) in enginesToReplace {
            guard isCurrent(command) else {
                return .superseded
            }

            engines.removeValue(forKey: appID)
            enqueueRetirement(engine)
        }

        guard isCurrent(command) else {
            return .superseded
        }

        guard waitForPendingAggregateRemoval(command: command) else {
            return .failed
        }

        return reconcileCurrentRoute(command, startsAtTargetGain: true) ? .applied : .failed
    }

    private func reconcileCurrentRoute(
        _ command: AppMixerCommand,
        startsAtTargetGain: Bool = false
    ) -> Bool {
        let currentIDs = Set(command.targets.map(\.id))
        var success = true

        for (appID, engine) in Array(engines) where !currentIDs.contains(appID) {
            guard isCurrent(command) else {
                return false
            }

            engines.removeValue(forKey: appID)
            enqueueRetirement(engine)
        }

        guard waitForPendingAggregateRemoval(command: command) else {
            return false
        }

        for target in command.targets {
            guard isCurrent(command) else {
                return false
            }

            if !apply(
                target,
                command: command,
                startsAtTargetGain: startsAtTargetGain
            ) {
                success = false
            }
        }

        return success
    }

    private func stopAllNow() {
        releaseOutputSwitchMuteGuard()
        for engine in engines.values {
            enqueueRetirement(engine)
        }

        engines.removeAll()
        _ = waitForPendingAggregateRemoval()
    }

    private func releaseOutputSwitchMuteGuard() {
        guard let outputSwitchMuteGuard else {
            return
        }

        let deadline = Date().addingTimeInterval(0.8)
        while !outputSwitchMuteGuard.isStopped, Date() < deadline {
            outputSwitchMuteGuard.stop()
            if !outputSwitchMuteGuard.isStopped {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        if outputSwitchMuteGuard.isStopped {
            self.outputSwitchMuteGuard = nil
        }
    }

    private func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }

    private func isCurrent(_ command: AppMixerCommand) -> Bool {
        isCurrent(revision: command.revision)
    }

    private func isCurrent(revision: UInt64) -> Bool {
        latestCommandRevision.load(ordering: .acquiring) == revision
    }

    private func enqueueRetirement(_ engine: any AppGainEngine) {
        let retirement = AppGainEngineRetirement(engine: engine)
        pendingRetirements.append(retirement)
        retirement.start(on: retirementQueue)
    }

    private func prepareForUnityHandoff(_ engines: [any AppGainEngine]) {
        guard !engines.isEmpty else {
            return
        }

        for engine in engines {
            engine.gain = 1
        }

        let deadline = Date().addingTimeInterval(Self.maximumGainHandoffDuration)
        while Date() < deadline {
            if engines.allSatisfy({ $0.hasRenderedGain(1) }) {
                return
            }

            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    private func pollForOutputSwitchQuiescence(
        revision: UInt64,
        deadline: UInt64,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        pendingRetirements.removeAll(where: \.isComplete)

        guard isCurrent(revision: revision) else {
            completion(.superseded)
            return
        }

        guard pendingRetirements.contains(where: { !$0.hasReleasedRoute }) else {
            completion(.applied)
            return
        }

        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            completion(.failed)
            return
        }

        lifecycleQueue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(Self.outputSwitchQuiescencePollNanoseconds))
        ) { [self] in
            pollForOutputSwitchQuiescence(
                revision: revision,
                deadline: deadline,
                completion: completion
            )
        }
    }

    private func waitForPendingAggregateRemoval(command: AppMixerCommand? = nil) -> Bool {
        guard !pendingRetirements.isEmpty else {
            return true
        }

        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline {
            if let command, !isCurrent(command) {
                return false
            }

            pendingRetirements.removeAll(where: \.shouldStopBlockingCommands)
            if pendingRetirements.isEmpty {
                return true
            }

            Thread.sleep(forTimeInterval: 0.02)
        }

        return false
    }

}

private protocol AppGainEngine: AnyObject {
    nonisolated var gain: Float { get set }
    nonisolated var tappedObjects: [AudioObjectID] { get }
    nonisolated var outputDeviceUID: String { get }
    nonisolated var isStopped: Bool { get }
    nonisolated func hasRenderedGain(_ gain: Float) -> Bool

    @discardableResult
    nonisolated func stop() -> AudioObjectID?
}

nonisolated private final class AppGainEngineRetirement: @unchecked Sendable {
    private static let maximumCoordinationWaitNanoseconds: UInt64 = 750_000_000
    private let engine: any AppGainEngine
    private let teardownCompletedAt = Atomic<UInt64>(0)
    private let completed = Atomic<Bool>(false)

    init(engine: any AppGainEngine) {
        self.engine = engine
    }

    var isComplete: Bool {
        completed.load(ordering: .acquiring)
    }

    var hasReleasedRoute: Bool {
        isComplete || teardownCompletedAt.load(ordering: .acquiring) > 0
    }

    var shouldStopBlockingCommands: Bool {
        if isComplete {
            return true
        }

        let completedAt = teardownCompletedAt.load(ordering: .acquiring)
        guard completedAt > 0 else {
            return false
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds &- completedAt
        return elapsed >= Self.maximumCoordinationWaitNanoseconds
    }

    func start(on queue: DispatchQueue) {
        queue.async { [self] in
            var retiredAggregateID: AudioObjectID?
            while !engine.isStopped {
                if let aggregateID = engine.stop() {
                    retiredAggregateID = retiredAggregateID ?? aggregateID
                }

                if !engine.isStopped {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            teardownCompletedAt.store(DispatchTime.now().uptimeNanoseconds, ordering: .releasing)

            if let retiredAggregateID {
                while true {
                    if let activeDeviceIDs = Self.activeAudioDeviceIDs(),
                       !activeDeviceIDs.contains(retiredAggregateID) {
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.02)
                }
            }

            completed.store(true, ordering: .releasing)
        }
    }

    private static func activeAudioDeviceIDs() -> Set<AudioObjectID>? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }

        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return nil
        }

        return Set(deviceIDs.filter { $0 != kAudioObjectUnknown })
    }
}

nonisolated private final class GainState: @unchecked Sendable {
    private static let rampDurationSeconds = 0.04
    private static let fallbackSampleRate = 48_000.0
    private let targetGain: Atomic<Float>
    private let renderedGain: Atomic<Float>
    // targetGain crosses threads atomically; the remaining fields belong exclusively to
    // the realtime IO callback after the engine starts.
    private var currentGain: Float
    private var lastTargetGain: Float
    private var remainingRampFrames: UInt32 = 0

    init(initialGain: Float, targetGain: Float) {
        let initialGain = Self.clamp(initialGain)
        let targetGain = Self.clamp(targetGain)
        self.currentGain = initialGain
        self.lastTargetGain = initialGain
        self.targetGain = Atomic(targetGain)
        self.renderedGain = Atomic(initialGain)
    }

    var target: Float {
        get { targetGain.load(ordering: .relaxed) }
        set { targetGain.store(Self.clamp(newValue), ordering: .relaxed) }
    }

    func hasRendered(_ gain: Float) -> Bool {
        abs(renderedGain.load(ordering: .relaxed) - Self.clamp(gain)) < 0.0001
    }

    func markRendered(_ ramp: GainRamp) {
        renderedGain.store(ramp.end, ordering: .relaxed)
    }

    func nextRamp(frameCount: UInt32, sampleRate: Float64) -> GainRamp {
        let target = targetGain.load(ordering: .relaxed)
        if abs(target - lastTargetGain) > 0.0001 {
            lastTargetGain = target
            let sampleRate = sampleRate.isFinite && sampleRate > 0
                ? sampleRate
                : Self.fallbackSampleRate
            let rampFrames = min(
                sampleRate * Self.rampDurationSeconds,
                Double(UInt32.max)
            )
            remainingRampFrames = max(UInt32(rampFrames.rounded(.up)), 1)
        }

        let start = currentGain
        guard remainingRampFrames > 0, frameCount > 0 else {
            currentGain = target
            return GainRamp(start: target, end: target, frameCount: 0)
        }

        let framesThisBuffer = min(frameCount, remainingRampFrames)
        let progress = Float(framesThisBuffer) / Float(remainingRampFrames)
        currentGain += (target - currentGain) * progress
        remainingRampFrames -= framesThisBuffer

        if remainingRampFrames == 0 {
            currentGain = target
        }

        return GainRamp(start: start, end: currentGain, frameCount: framesThisBuffer)
    }

    private static func clamp(_ gain: Float) -> Float {
        max(0, min(AppAudioMixer.maximumGain, gain))
    }
}

nonisolated private struct GainRamp: Sendable {
    let start: Float
    let end: Float
    let frameCount: UInt32
}

@available(macOS 14.4, *)
nonisolated private final class ProcessTapMuteGuard {
    nonisolated var isStopped: Bool {
        ioProc == nil
            && aggregateID == kAudioObjectUnknown
            && tapID == kAudioObjectUnknown
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var isRunning = false

    init?(audioObjectIDs: [AudioObjectID]) {
        guard !audioObjectIDs.isEmpty else {
            return nil
        }

        let tapDescription = CATapDescription(
            stereoMixdownOfProcesses: audioObjectIDs
        )
        tapDescription.name = "MacMix Route Switch Guard"
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true

        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr,
              tapID != kAudioObjectUnknown else {
            return nil
        }

        // This aggregate intentionally has no physical subdevice. It only keeps the
        // process tap running while the old output aggregate is removed and HAL changes
        // routes, so it cannot keep a Bluetooth output session alive or claim dOut.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacMix Route Switch Guard",
            kAudioAggregateDeviceUIDKey: "MacMix.RouteGuard.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: false,
                ],
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        guard AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        ) == noErr,
              aggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            return nil
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProc,
            aggregateID,
            nil
        ) { _, _, _, _, _ in }
        guard status == noErr, let ioProc else {
            stop()
            return nil
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return nil
        }
        isRunning = true
    }

    nonisolated func stop() {
        if let ioProc {
            if isRunning {
                let status = AudioDeviceStop(aggregateID, ioProc)
                if Self.didStop(status) {
                    isRunning = false
                } else {
                    return
                }
            }

            let status = AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            if Self.didDestroy(status) || !Self.audioObjectExists(aggregateID) {
                self.ioProc = nil
            } else {
                return
            }
        }

        if aggregateID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateID)
            if Self.didDestroy(status) || !Self.audioObjectExists(aggregateID) {
                aggregateID = kAudioObjectUnknown
            } else {
                return
            }
        }

        if tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            if Self.didDestroy(status) || !Self.audioObjectExists(tapID) {
                tapID = kAudioObjectUnknown
            }
        }
    }

    deinit {
        stop()
    }

    private static func didStop(_ status: OSStatus) -> Bool {
        status == noErr
            || status == kAudioHardwareNotRunningError
            || didDestroy(status)
    }

    private static func didDestroy(_ status: OSStatus) -> Bool {
        status == noErr
            || status == kAudioHardwareBadObjectError
            || status == kAudioHardwareBadDeviceError
    }

    private static func audioObjectExists(_ objectID: AudioObjectID) -> Bool {
        guard objectID != kAudioObjectUnknown else {
            return false
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(objectID, &address)
    }
}

@available(macOS 14.4, *)
nonisolated private final class ProcessTapGainEngine: AppGainEngine {
    nonisolated let tappedObjects: [AudioObjectID]
    nonisolated let outputDeviceUID: String

    nonisolated var gain: Float {
        get { gainState.target }
        set { gainState.target = newValue }
    }

    nonisolated func hasRenderedGain(_ gain: Float) -> Bool {
        gainState.hasRendered(gain)
    }

    nonisolated var isStopped: Bool {
        ioProc == nil
            && aggregateID == kAudioObjectUnknown
            && tapID == kAudioObjectUnknown
    }

    private let gainState: GainState
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var isRunning = false

    private struct OutputStreamCandidate {
        let index: UInt
        let format: AudioStreamBasicDescription
        let isActive: Bool
    }

    private struct ProcessTapConfiguration {
        let description: CATapDescription
        let outputBufferOffset: Int
    }

    init?(
        audioObjectIDs: [AudioObjectID],
        initialGain: Float,
        gain: Float,
        outputDeviceUID: String
    ) {
        guard !audioObjectIDs.isEmpty else {
            return nil
        }

        self.tappedObjects = audioObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.gainState = GainState(initialGain: initialGain, targetGain: gain)

        guard let tapConfiguration = Self.createProcessTap(
            audioObjectIDs: audioObjectIDs,
            outputDeviceUID: outputDeviceUID,
            tapID: &tapID
        ) else {
            return nil
        }

        guard let tapFormat = Self.tapFormat(for: tapID) else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacMix Mixer",
            kAudioAggregateDeviceUIDKey: "MacMix.Mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapConfiguration.description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let gainState = gainState
        let outputBufferOffset = tapConfiguration.outputBufferOffset
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inputData, _, outputData, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            let bytesPerFrame = max(tapFormat.mBytesPerFrame, 1)
            var frameCount: UInt32?
            for (index, inputBuffer) in inputBuffers.enumerated() {
                let outputIndex = outputBufferOffset + index
                guard outputIndex < outputBuffers.count,
                      inputBuffer.mData != nil,
                      outputBuffers[outputIndex].mData != nil,
                      inputBuffer.mNumberChannels == outputBuffers[outputIndex].mNumberChannels,
                      outputBuffers[outputIndex].mDataByteSize >= inputBuffer.mDataByteSize,
                      inputBuffer.mDataByteSize > 0 else {
                    continue
                }

                frameCount = inputBuffer.mDataByteSize / bytesPerFrame
                break
            }

            guard let frameCount, frameCount > 0 else {
                return
            }

            let gainRamp = gainState.nextRamp(frameCount: frameCount, sampleRate: tapFormat.mSampleRate)
            var didWriteAudio = false

            for (index, inputBuffer) in inputBuffers.enumerated() {
                let outputIndex = outputBufferOffset + index
                guard outputIndex < outputBuffers.count,
                      inputBuffer.mData != nil,
                      outputBuffers[outputIndex].mData != nil,
                      inputBuffer.mNumberChannels == outputBuffers[outputIndex].mNumberChannels,
                      outputBuffers[outputIndex].mDataByteSize >= inputBuffer.mDataByteSize else {
                    continue
                }

                if Self.writeScaledAudio(
                    from: inputBuffer,
                    to: outputBuffers[outputIndex],
                    gainRamp: gainRamp,
                    format: tapFormat
                ) {
                    didWriteAudio = true
                }
            }

            if didWriteAudio {
                gainState.markRendered(gainRamp)
            }
        }

        guard status == noErr, let ioProc else {
            stopAfterInitializationFailure()
            return nil
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stopAfterInitializationFailure()
            return nil
        }

        isRunning = true
    }

    @discardableResult
    nonisolated func stop() -> AudioObjectID? {
        let retiredAggregateID = aggregateID != kAudioObjectUnknown ? aggregateID : nil

        if aggregateID != kAudioObjectUnknown,
           !Self.audioObjectExists(aggregateID) {
            ioProc = nil
            isRunning = false
            aggregateID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown,
           !Self.audioObjectExists(tapID) {
            tapID = kAudioObjectUnknown
        }

        if let ioProc {
            if isRunning {
                let status = AudioDeviceStop(aggregateID, ioProc)
                if Self.didStop(status) {
                    isRunning = false
                } else {
                    return retiredAggregateID
                }
            }

            let status = AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            if Self.didDestroy(status) || !Self.audioObjectExists(aggregateID) {
                self.ioProc = nil
            } else {
                return retiredAggregateID
            }
        }

        if aggregateID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateID)
            if Self.didDestroy(status) || !Self.audioObjectExists(aggregateID) {
                aggregateID = kAudioObjectUnknown
            } else {
                return retiredAggregateID
            }
        }

        if tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            if Self.didDestroy(status) || !Self.audioObjectExists(tapID) {
                tapID = kAudioObjectUnknown
            }
        }

        return retiredAggregateID
    }

    deinit {
        stop()
    }

    private func stopAfterInitializationFailure() {
        var retiredAggregateIDs: Set<AudioObjectID> = []
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline {
            if let retiredAggregateID = stop() {
                retiredAggregateIDs.insert(retiredAggregateID)
            }

            if let activeDeviceIDs = Self.activeAudioDeviceIDs() {
                retiredAggregateIDs.formIntersection(activeDeviceIDs)
                if isStopped, retiredAggregateIDs.isEmpty {
                    return
                }
            }

            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private static func didStop(_ status: OSStatus) -> Bool {
        status == noErr
            || status == kAudioHardwareNotRunningError
            || didDestroy(status)
    }

    private static func didDestroy(_ status: OSStatus) -> Bool {
        status == noErr
            || status == kAudioHardwareBadObjectError
            || status == kAudioHardwareBadDeviceError
    }

    private static func audioObjectExists(_ objectID: AudioObjectID) -> Bool {
        guard objectID != kAudioObjectUnknown else {
            return false
        }

        var address = propertyAddress(selector: kAudioObjectPropertyClass)
        return AudioObjectHasProperty(objectID, &address)
    }

    private static func activeAudioDeviceIDs() -> Set<AudioObjectID>? {
        var address = propertyAddress(selector: kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return nil
        }

        return Set(deviceIDs.filter { $0 != kAudioObjectUnknown })
    }

    private static func createProcessTap(
        audioObjectIDs: [AudioObjectID],
        outputDeviceUID: String,
        tapID: inout AudioObjectID
    ) -> ProcessTapConfiguration? {
        // A stream tap preserves a multichannel device's PCM layout. Falling back to a stereo
        // tap on that device would make the aggregate input/output buffer layouts incompatible.
        let stereoMixdownTap = Self.configure(
            CATapDescription(stereoMixdownOfProcesses: audioObjectIDs),
            name: "MacMix Stereo Mixdown"
        )
        let candidates: [ProcessTapConfiguration]
        if let outputStreamIndex = preferredMultichannelOutputStreamIndex(outputDeviceUID: outputDeviceUID) {
            let outputStreamTap = Self.configure(
                CATapDescription(processes: audioObjectIDs, deviceUID: outputDeviceUID, stream: outputStreamIndex),
                name: "MacMix Output Stream \(outputStreamIndex)"
            )
            candidates = [
                ProcessTapConfiguration(
                    description: outputStreamTap,
                    outputBufferOffset: outputBufferOffset(
                        outputDeviceUID: outputDeviceUID,
                        streamIndex: outputStreamIndex
                    )
                ),
            ]
        } else {
            candidates = [
                ProcessTapConfiguration(
                    description: stereoMixdownTap,
                    outputBufferOffset: 0
                ),
            ]
        }

        for configuration in candidates {
            tapID = AudioObjectID(kAudioObjectUnknown)

            if AudioHardwareCreateProcessTap(configuration.description, &tapID) == noErr,
               tapID != kAudioObjectUnknown {
                return configuration
            }
        }

        tapID = AudioObjectID(kAudioObjectUnknown)
        return nil
    }

    @discardableResult
    private static func configure(_ tapDescription: CATapDescription, name: String) -> CATapDescription {
        tapDescription.name = name
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        return tapDescription
    }

    private static func preferredMultichannelOutputStreamIndex(outputDeviceUID: String) -> UInt? {
        guard let deviceID = deviceID(forUID: outputDeviceUID) else {
            return nil
        }

        return outputStreamCandidates(deviceID: deviceID)
            .filter { $0.format.mChannelsPerFrame > 2 }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }

                if lhs.format.mChannelsPerFrame != rhs.format.mChannelsPerFrame {
                    return lhs.format.mChannelsPerFrame > rhs.format.mChannelsPerFrame
                }

                return lhs.index < rhs.index
            }
            .first?
            .index
    }

    private static func outputBufferOffset(outputDeviceUID: String, streamIndex: UInt) -> Int {
        guard let deviceID = deviceID(forUID: outputDeviceUID) else {
            return 0
        }

        return outputStreamCandidates(deviceID: deviceID)
            .filter { $0.index < streamIndex }
            .reduce(0) { offset, candidate in
                let isNonInterleaved = candidate.format.mFormatFlags
                    & kAudioFormatFlagIsNonInterleaved != 0
                return offset + (isNonInterleaved ? Int(candidate.format.mChannelsPerFrame) : 1)
            }
    }

    private static func outputStreamCandidates(deviceID: AudioObjectID) -> [OutputStreamCandidate] {
        audioObjectIDs(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        )
        .enumerated()
        .compactMap { streamIndex, streamID in
            guard let format = streamFormat(streamID: streamID) else {
                return nil
            }

            return OutputStreamCandidate(
                index: UInt(streamIndex),
                format: format,
                isActive: boolProperty(streamID, selector: kAudioStreamPropertyIsActive)
            )
        }
    }

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )
        .first { deviceID in
            stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) == uid
        }
    }

    private static func audioObjectIDs(
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

    private static func stringProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
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

    private static func boolProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var address = propertyAddress(selector: selector)
        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    private static func streamFormat(streamID: AudioStreamID) -> AudioStreamBasicDescription? {
        var address = propertyAddress(selector: kAudioStreamPropertyVirtualFormat)
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(streamID, &address, 0, nil, &dataSize, &format)

        return status == noErr ? format : nil
    }

    private static func propertyAddress(
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

    private static func tapFormat(for tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format)

        return status == noErr ? format : nil
    }

    private static func writeScaledAudio(
        from inputBuffer: AudioBuffer,
        to outputBuffer: AudioBuffer,
        gainRamp: GainRamp,
        format: AudioStreamBasicDescription
    ) -> Bool {
        guard let source = inputBuffer.mData,
              let destination = outputBuffer.mData else {
            return false
        }

        let inputByteCount = Int(inputBuffer.mDataByteSize)
        let outputByteCount = Int(outputBuffer.mDataByteSize)
        let byteCount = min(inputByteCount, outputByteCount)

        guard byteCount > 0 else {
            return false
        }

        guard format.mFormatID == kAudioFormatLinearPCM else {
            copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            return true
        }

        let flags = format.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let channelCount = max(1, Int(inputBuffer.mNumberChannels))

        if isFloat {
            switch format.mBitsPerChannel {
            case 32:
                writeScaledFloat32(
                    from: source,
                    to: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            case 64:
                writeScaledFloat64(
                    from: source,
                    to: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            default:
                copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            }
        } else if isSignedInteger {
            switch format.mBitsPerChannel {
            case 16:
                writeScaledInt16(
                    from: source,
                    to: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            case 24:
                if !writeScaledInt24(
                    from: source,
                    to: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount,
                    format: format
                ) {
                    copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
                }
            case 32:
                writeScaledInt32(
                    from: source,
                    to: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            default:
                copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            }
        } else {
            copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
        }

        zeroRemainingAudio(in: destination, byteCount: byteCount, outputByteCount: outputByteCount)
        return true
    }

    private static func writeScaledFloat32(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            return
        }

        let channelCount = max(1, min(channelCount, sampleCount))
        let frameCount = sampleCount / channelCount
        guard frameCount > 0 else {
            return
        }

        let source = source.assumingMemoryBound(to: Float.self)
        let destination = destination.assumingMemoryBound(to: Float.self)
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)

        if rampFrameCount > 0 {
            var step = (gainRamp.end - gainRamp.start) / Float(rampFrameCount)
            for channel in 0..<channelCount {
                var start = gainRamp.start
                vDSP_vrampmul(
                    source.advanced(by: channel),
                    vDSP_Stride(channelCount),
                    &start,
                    &step,
                    destination.advanced(by: channel),
                    vDSP_Stride(channelCount),
                    vDSP_Length(rampFrameCount)
                )
            }
        }

        scaleRemainingSamples(
            from: source,
            to: destination,
            startIndex: rampFrameCount * channelCount,
            sampleCount: sampleCount,
            gain: gainRamp.end
        )
    }

    private static func writeScaledFloat64(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Double>.size
        guard sampleCount > 0 else {
            return
        }

        let channelCount = max(1, min(channelCount, sampleCount))
        let frameCount = sampleCount / channelCount
        guard frameCount > 0 else {
            return
        }

        let source = source.assumingMemoryBound(to: Double.self)
        let destination = destination.assumingMemoryBound(to: Double.self)
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)

        if rampFrameCount > 0 {
            let startGain = Double(gainRamp.start)
            var step = (Double(gainRamp.end) - startGain) / Double(rampFrameCount)
            for channel in 0..<channelCount {
                var start = startGain
                vDSP_vrampmulD(
                    source.advanced(by: channel),
                    vDSP_Stride(channelCount),
                    &start,
                    &step,
                    destination.advanced(by: channel),
                    vDSP_Stride(channelCount),
                    vDSP_Length(rampFrameCount)
                )
            }
        }

        scaleRemainingSamples(
            from: source,
            to: destination,
            startIndex: rampFrameCount * channelCount,
            sampleCount: sampleCount,
            gain: Double(gainRamp.end)
        )
    }

    private static func scaleRemainingSamples(
        from source: UnsafePointer<Float>,
        to destination: UnsafeMutablePointer<Float>,
        startIndex: Int,
        sampleCount: Int,
        gain: Float
    ) {
        guard startIndex < sampleCount else {
            return
        }

        for index in startIndex..<sampleCount {
            destination[index] = source[index] * gain
        }
    }

    private static func scaleRemainingSamples(
        from source: UnsafePointer<Double>,
        to destination: UnsafeMutablePointer<Double>,
        startIndex: Int,
        sampleCount: Int,
        gain: Double
    ) {
        guard startIndex < sampleCount else {
            return
        }

        for index in startIndex..<sampleCount {
            destination[index] = source[index] * gain
        }
    }

    private static func writeScaledInt16(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int16>.size
        let source = source.assumingMemoryBound(to: Int16.self)
        let destination = destination.assumingMemoryBound(to: Int16.self)
        let channelCount = max(1, min(channelCount, max(sampleCount, 1)))
        let frameCount = sampleCount / channelCount
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)
        let gainStep = rampFrameCount > 0
            ? (gainRamp.end - gainRamp.start) / Float(rampFrameCount)
            : 0

        for index in 0..<sampleCount {
            let frame = min(index / channelCount, max(frameCount - 1, 0))
            let gain = frame < rampFrameCount
                ? gainRamp.start + Float(frame) * gainStep
                : gainRamp.end
            let scaledSample = (Double(source[index]) * Double(gain)).rounded()
            destination[index] = Int16(clamping: Int(scaledSample))
        }
    }

    private static func writeScaledInt32(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int32>.size
        let source = source.assumingMemoryBound(to: Int32.self)
        let destination = destination.assumingMemoryBound(to: Int32.self)
        let channelCount = max(1, min(channelCount, max(sampleCount, 1)))
        let frameCount = sampleCount / channelCount
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)
        let gainStep = rampFrameCount > 0
            ? (gainRamp.end - gainRamp.start) / Float(rampFrameCount)
            : 0

        for index in 0..<sampleCount {
            let frame = min(index / channelCount, max(frameCount - 1, 0))
            let gain = frame < rampFrameCount
                ? gainRamp.start + Float(frame) * gainStep
                : gainRamp.end
            let scaledSample = (Double(source[index]) * Double(gain)).rounded()
            destination[index] = Int32(clamping: Int64(scaledSample))
        }
    }

    private static func writeScaledInt24(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int,
        format: AudioStreamBasicDescription
    ) -> Bool {
        let flags = format.mFormatFlags
        let isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
        let isAlignedHigh = flags & kAudioFormatFlagIsAlignedHigh != 0
        let isNonInterleaved = flags & kAudioFormatFlagIsNonInterleaved != 0
        let channelsPerFrame = max(1, Int(format.mChannelsPerFrame))
        let bytesPerFrame = Int(format.mBytesPerFrame)
        let bytesPerSample = bytesPerFrame > 0
            ? (isNonInterleaved ? bytesPerFrame : max(1, bytesPerFrame / channelsPerFrame))
            : 3

        guard bytesPerSample == 3 || bytesPerSample == 4 else {
            return false
        }

        let sampleCount = byteCount / bytesPerSample
        guard sampleCount > 0 else {
            return true
        }

        let source = source.assumingMemoryBound(to: UInt8.self)
        let destination = destination.assumingMemoryBound(to: UInt8.self)
        let channelCount = max(1, min(channelCount, sampleCount))
        let frameCount = sampleCount / channelCount
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)
        let gainStep = rampFrameCount > 0
            ? (gainRamp.end - gainRamp.start) / Float(rampFrameCount)
            : 0

        for index in 0..<sampleCount {
            let offset = index * bytesPerSample
            let frame = min(index / channelCount, max(frameCount - 1, 0))
            let gain = frame < rampFrameCount
                ? gainRamp.start + Float(frame) * gainStep
                : gainRamp.end
            let sample = readSignedInt24(
                from: source.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
            let scaledSample = clampInt24((Double(sample) * Double(gain)).rounded())

            writeSignedInt24(
                scaledSample,
                to: destination.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
        }

        return true
    }

    private static func readSignedInt24(
        from source: UnsafePointer<UInt8>,
        bytesPerSample: Int,
        isBigEndian: Bool,
        isAlignedHigh: Bool
    ) -> Int32 {
        if bytesPerSample == 4 {
            let raw32 = readSignedInt32Bytes(from: source, isBigEndian: isBigEndian)
            return isAlignedHigh ? raw32 >> 8 : signExtendInt24(raw32 & 0x00FF_FFFF)
        }

        let raw24: Int32
        if isBigEndian {
            raw24 = Int32(source[0]) << 16
                | Int32(source[1]) << 8
                | Int32(source[2])
        } else {
            raw24 = Int32(source[0])
                | Int32(source[1]) << 8
                | Int32(source[2]) << 16
        }

        return signExtendInt24(raw24)
    }

    private static func writeSignedInt24(
        _ sample: Int32,
        to destination: UnsafeMutablePointer<UInt8>,
        bytesPerSample: Int,
        isBigEndian: Bool,
        isAlignedHigh: Bool
    ) {
        if bytesPerSample == 4 {
            let raw32 = isAlignedHigh ? sample << 8 : sample & 0x00FF_FFFF
            writeSignedInt32Bytes(raw32, to: destination, isBigEndian: isBigEndian)
            return
        }

        let raw24 = sample & 0x00FF_FFFF
        if isBigEndian {
            destination[0] = UInt8((raw24 >> 16) & 0xFF)
            destination[1] = UInt8((raw24 >> 8) & 0xFF)
            destination[2] = UInt8(raw24 & 0xFF)
        } else {
            destination[0] = UInt8(raw24 & 0xFF)
            destination[1] = UInt8((raw24 >> 8) & 0xFF)
            destination[2] = UInt8((raw24 >> 16) & 0xFF)
        }
    }

    private static func readSignedInt32Bytes(from source: UnsafePointer<UInt8>, isBigEndian: Bool) -> Int32 {
        let raw: UInt32
        if isBigEndian {
            raw = UInt32(source[0]) << 24
                | UInt32(source[1]) << 16
                | UInt32(source[2]) << 8
                | UInt32(source[3])
        } else {
            raw = UInt32(source[0])
                | UInt32(source[1]) << 8
                | UInt32(source[2]) << 16
                | UInt32(source[3]) << 24
        }

        return Int32(bitPattern: raw)
    }

    private static func writeSignedInt32Bytes(
        _ sample: Int32,
        to destination: UnsafeMutablePointer<UInt8>,
        isBigEndian: Bool
    ) {
        let raw = UInt32(bitPattern: sample)
        if isBigEndian {
            destination[0] = UInt8((raw >> 24) & 0xFF)
            destination[1] = UInt8((raw >> 16) & 0xFF)
            destination[2] = UInt8((raw >> 8) & 0xFF)
            destination[3] = UInt8(raw & 0xFF)
        } else {
            destination[0] = UInt8(raw & 0xFF)
            destination[1] = UInt8((raw >> 8) & 0xFF)
            destination[2] = UInt8((raw >> 16) & 0xFF)
            destination[3] = UInt8((raw >> 24) & 0xFF)
        }
    }

    private static func signExtendInt24(_ value: Int32) -> Int32 {
        value & 0x0080_0000 != 0 ? value | ~0x00FF_FFFF : value
    }

    private static func clampInt24(_ value: Double) -> Int32 {
        Int32(max(-8_388_608, min(8_388_607, value)))
    }

    private static func copyAudio(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        byteCount: Int,
        outputByteCount: Int
    ) {
        memcpy(destination, source, byteCount)
        zeroRemainingAudio(in: destination, byteCount: byteCount, outputByteCount: outputByteCount)
    }

    private static func zeroRemainingAudio(
        in destination: UnsafeMutableRawPointer,
        byteCount: Int,
        outputByteCount: Int
    ) {
        guard outputByteCount > byteCount else {
            return
        }

        memset(destination.advanced(by: byteCount), 0, outputByteCount - byteCount)
    }
}
