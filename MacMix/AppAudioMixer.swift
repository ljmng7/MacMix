//
//  AppAudioMixer.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import Accelerate
import Atomics
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

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
    private var engine: (any AppGainEngine)?
    private var pendingRetirements: [AppGainEngineRetirement] = []
    private var outputSwitchMuteGuard: ProcessTapMuteGuard?
    private let latestCommandRevision = ManagedAtomic<UInt64>(0)

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
            let engineToRetire = engine
            let guardedAudioObjectIDs = Set(
                (engineToRetire?.tappedObjects ?? [])
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
                prepareForUnityHandoff(engineToRetire)
            }

            guard isCurrent(revision: revision) else {
                completion(.superseded)
                return
            }

            engine = nil
            if let engineToRetire {
                enqueueRetirement(engineToRetire)
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
        latestCommandRevision.wrappingIncrement(ordering: .releasing)
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

    private func reconcile(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command) else {
            return .superseded
        }

        return reconcileCurrentRoute(command) ? .applied : .failed
    }

    private func transition(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command) else {
            return .superseded
        }

        return reconcileCurrentRoute(command, startsAtTargetGain: true) ? .applied : .failed
    }

    private func reconcileCurrentRoute(
        _ command: AppMixerCommand,
        startsAtTargetGain: Bool = false
    ) -> Bool {
        guard isCurrent(command) else {
            return false
        }

        let routableTargets = command.targets.filter {
            !$0.audioObjectIDs.isEmpty
        }
        let activeTargets = routableTargets.filter {
            !isUnity($0.volume)
        }

        guard !activeTargets.isEmpty else {
            guard let oldEngine = engine else {
                return true
            }

            engine = nil
            prepareForUnityHandoff(oldEngine)
            enqueueRetirement(oldEngine)
            return waitForPendingAggregateRemoval(command: command)
        }

        guard Self.isSupported, let outputDeviceUID = command.outputDeviceUID else {
            return false
        }

        let graphTargets: [AppMixTarget]
        if let engine, engine.outputDeviceUID == outputDeviceUID {
            // Once an app joins the shared graph, keep its tap at unity so crossing
            // 100% never tears down the graph and interrupts the other mixed apps.
            graphTargets = routableTargets.filter {
                !isUnity($0.volume) || engine.containsTarget($0.id)
            }
        } else {
            graphTargets = activeTargets
        }

        if let engine,
           engine.outputDeviceUID == outputDeviceUID,
           engine.updateGraphIfPossible(graphTargets) {
            for target in graphTargets {
                engine.setGain(clampedGain(target.volume), for: target.id)
            }
            return isCurrent(command)
        }

        if let oldEngine = engine {
            engine = nil
            prepareForUnityHandoff(oldEngine)
            enqueueRetirement(oldEngine)
        }

        guard waitForPendingAggregateRemoval(command: command), isCurrent(command) else {
            return false
        }

        guard #available(macOS 14.4, *),
              let newEngine = SharedProcessTapGainEngine(
                targets: graphTargets,
                startsAtTargetGain: startsAtTargetGain,
                outputDeviceUID: outputDeviceUID
              ) else {
            return false
        }

        guard isCurrent(command) else {
            enqueueRetirement(newEngine)
            _ = waitForPendingAggregateRemoval(command: command)
            return false
        }

        engine = newEngine
        return true
    }

    private func stopAllNow() {
        releaseOutputSwitchMuteGuard()
        if let engine {
            enqueueRetirement(engine)
        }

        engine = nil
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

    private func clampedGain(_ volume: Double) -> Float {
        Float(max(0, min(Double(Self.maximumGain), volume)))
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

    private func prepareForUnityHandoff(_ engine: (any AppGainEngine)?) {
        guard let engine else {
            return
        }

        engine.setAllGains(1)

        let deadline = Date().addingTimeInterval(Self.maximumGainHandoffDuration)
        while Date() < deadline {
            if engine.hasRenderedAllGains(1) {
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
    nonisolated var tappedObjects: [AudioObjectID] { get }
    nonisolated var outputDeviceUID: String { get }
    nonisolated var isStopped: Bool { get }
    nonisolated func containsTarget(_ targetID: String) -> Bool
    nonisolated func updateGraphIfPossible(_ targets: [AppMixTarget]) -> Bool
    nonisolated func setGain(_ gain: Float, for targetID: String)
    nonisolated func setAllGains(_ gain: Float)
    nonisolated func hasRenderedAllGains(_ gain: Float) -> Bool

    @discardableResult
    nonisolated func stop() -> AudioObjectID?
}

nonisolated private final class AppGainEngineRetirement: @unchecked Sendable {
    private static let maximumCoordinationWaitNanoseconds: UInt64 = 750_000_000
    private let engine: any AppGainEngine
    private let teardownCompletedAt = ManagedAtomic<UInt64>(0)
    private let completed = ManagedAtomic<Bool>(false)

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
        guard let deviceIDs = readHALAudioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        ) else {
            return nil
        }

        return Set(deviceIDs)
    }
}

nonisolated private final class GainState: @unchecked Sendable {
    private let context: MacMixAudioIOContextRef
    private let configurationIndex: Int

    init(context: MacMixAudioIOContextRef, configurationIndex: Int) {
        self.context = context
        self.configurationIndex = configurationIndex
        MacMixAudioIOContextRetain(context)
    }

    deinit {
        MacMixAudioIOContextDestroy(context)
    }

    func setTarget(_ gain: Float) {
        MacMixAudioIOContextSetTargetGain(
            context,
            configurationIndex,
            Self.clamp(gain)
        )
    }

    func hasRendered(_ gain: Float) -> Bool {
        abs(
            MacMixAudioIOContextRenderedGain(context, configurationIndex)
                - Self.clamp(gain)
        ) < 0.0001
    }

    private static func clamp(_ gain: Float) -> Float {
        max(0, min(AppAudioMixer.maximumGain, gain))
    }
}

// Kept as the reference representation for the format-specific mixing helpers below.
// The realtime callback uses the equivalent C representation in MacMixAudioIOProc.c.
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

        let status = AudioDeviceCreateIOProcID(
            aggregateID,
            MacMixNoopAudioDeviceIOProc,
            nil,
            &ioProc
        )
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
nonisolated private final class SharedProcessTapGainEngine: AppGainEngine {
    private static let tapDescriptionUpdateTimeout: TimeInterval = 0.25
    private static let tapPropertyQueue = DispatchQueue(
        label: "MacMix.ProcessTap.PropertyConfirmation"
    )
    private static let diagnosticsLogger = Logger(
        subsystem: "jazmin.MacMix",
        category: "AudioMixerDiagnostics"
    )

    nonisolated private(set) var tappedObjects: [AudioObjectID]
    nonisolated let outputDeviceUID: String

    nonisolated func containsTarget(_ targetID: String) -> Bool {
        tapBindings[targetID] != nil
    }

    nonisolated func updateGraphIfPossible(_ targets: [AppMixTarget]) -> Bool {
        let nextGraph = Self.graph(for: targets)
        guard nextGraph != graph else {
            return true
        }

        // Existing tap slots can be retargeted without changing the aggregate device's
        // stream layout. A completely new target still takes the full rebuild path
        // because the realtime callback has no gain slot for it.
        guard nextGraph.keys.allSatisfy({ tapBindings[$0] != nil }) else {
            return false
        }

        var updatedGraph = graph
        for (targetID, nextAudioObjectIDs) in nextGraph {
            guard let binding = tapBindings[targetID] else {
                return false
            }
            guard nextAudioObjectIDs != binding.audioObjectIDs else {
                updatedGraph[targetID] = nextAudioObjectIDs
                continue
            }

            guard Self.setProcesses(nextAudioObjectIDs, on: binding) else {
                // Process objects for browsers and media apps can churn while the
                // owning app remains alive. Keep the current tap and retry on the next
                // reconciliation instead of tearing down the shared aggregate device,
                // which would interrupt every other mixed app.
                Self.diagnosticsLogger.error(
                    "Deferring tap process update tap=\(binding.tapID) currentCount=\(binding.audioObjectIDs.count) requestedCount=\(nextAudioObjectIDs.count)"
                )
                continue
            }

            updatedGraph[targetID] = nextAudioObjectIDs
        }

        for targetID in graph.keys where nextGraph[targetID] == nil {
            gainStates[targetID]?.setTarget(1)
            updatedGraph.removeValue(forKey: targetID)
            if let binding = tapBindings[targetID] {
                // Keep the original process list attached to this tap. Clearing it can
                // make Core Audio reject the description update and would force the
                // shared aggregate device and IOProc to be rebuilt, interrupting the
                // remaining apps. A departed process produces no audio; unity also
                // preserves passthrough if process discovery is only briefly stale.
                Self.diagnosticsLogger.notice(
                    "Keeping inactive tap slot tap=\(binding.tapID) processCount=\(binding.audioObjectIDs.count)"
                )
            }
        }
        graph = updatedGraph
        tappedObjects = tapBindings.values.flatMap(\.audioObjectIDs)
        return true
    }

    nonisolated func setGain(_ gain: Float, for targetID: String) {
        gainStates[targetID]?.setTarget(gain)
    }

    nonisolated func setAllGains(_ gain: Float) {
        for gainState in gainStates.values {
            gainState.setTarget(gain)
        }
    }

    nonisolated func hasRenderedAllGains(_ gain: Float) -> Bool {
        gainStates.values.allSatisfy { $0.hasRendered(gain) }
    }

    nonisolated var isStopped: Bool {
        ioProc == nil
            && audioIOContext == nil
            && aggregateID == kAudioObjectUnknown
            && tapIDs.allSatisfy { $0 == kAudioObjectUnknown }
    }

    private var graph: [String: [AudioObjectID]]
    private var gainStates: [String: GainState] = [:]
    private var tapBindings: [String: TapBinding] = [:]
    private var tapIDs: [AudioObjectID] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var audioIOContext: MacMixAudioIOContextRef?
    private var isRunning = false

    private struct OutputStreamCandidate {
        let index: UInt
        let format: AudioStreamBasicDescription
        let isActive: Bool
    }

    private enum OutputStreamSelectionRead {
        case stream(index: UInt, outputBufferOffset: Int)
        case noStreams
        case failed
    }

    private struct ProcessTapConfiguration {
        let description: CATapDescription
        let outputBufferOffset: Int
        let requiresDriftCompensation: Bool
    }

    private struct TapRuntime: @unchecked Sendable {
        let targetID: String
        let description: CATapDescription
        let format: AudioStreamBasicDescription
        let inputBufferOffset: Int
        let inputBufferCount: Int
        let outputBufferOffset: Int
        let requiresDriftCompensation: Bool
        let initialGain: Float
        let targetGain: Float
    }

    private final class TapBinding {
        let tapID: AudioObjectID
        let description: CATapDescription
        var audioObjectIDs: [AudioObjectID]

        init(
            tapID: AudioObjectID,
            description: CATapDescription,
            audioObjectIDs: [AudioObjectID]
        ) {
            self.tapID = tapID
            self.description = description
            self.audioObjectIDs = audioObjectIDs
        }
    }

    init?(
        targets: [AppMixTarget],
        startsAtTargetGain: Bool,
        outputDeviceUID: String
    ) {
        let targets = targets.filter { !$0.audioObjectIDs.isEmpty }
        guard !targets.isEmpty else {
            return nil
        }

        self.graph = Self.graph(for: targets)
        self.tappedObjects = targets.flatMap(\.audioObjectIDs)
        self.outputDeviceUID = outputDeviceUID
        var tapRuntimes: [TapRuntime] = []
        var nextInputBufferOffset = 0
        for target in targets {
            var tapID = AudioObjectID(kAudioObjectUnknown)
            guard let configuration = Self.createProcessTap(
                audioObjectIDs: target.audioObjectIDs,
                outputDeviceUID: outputDeviceUID,
                tapID: &tapID
            ), let format = Self.tapFormat(for: tapID) else {
                if tapID != kAudioObjectUnknown {
                    AudioHardwareDestroyProcessTap(tapID)
                }
                stopAfterInitializationFailure()
                return nil
            }

            tapIDs.append(tapID)
            tapBindings[target.id] = TapBinding(
                tapID: tapID,
                description: configuration.description,
                audioObjectIDs: target.audioObjectIDs
            )
            let inputBufferCount = Self.bufferCount(for: format)
            let gain = Self.clampedGain(target.volume)
            tapRuntimes.append(
                TapRuntime(
                    targetID: target.id,
                    description: configuration.description,
                    format: format,
                    inputBufferOffset: nextInputBufferOffset,
                    inputBufferCount: inputBufferCount,
                    outputBufferOffset: configuration.outputBufferOffset,
                    requiresDriftCompensation: configuration.requiresDriftCompensation,
                    initialGain: startsAtTargetGain ? gain : 1,
                    targetGain: gain
                )
            )
            nextInputBufferOffset += inputBufferCount
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacMix Mixer",
            kAudioAggregateDeviceUIDKey: "MacMix.Mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: tapRuntimes.map { runtime in
                var description: [String: Any] = [
                    kAudioSubTapUIDKey: runtime.description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: runtime.requiresDriftCompensation,
                ]
                if runtime.requiresDriftCompensation {
                    description[kAudioSubTapDriftCompensationQualityKey] =
                        kAudioAggregateDriftCompensationMaxQuality
                }
                return description
            },
        ]

        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            stopAfterInitializationFailure()
            return nil
        }

        Self.logGraphDiagnostics(
            aggregateID: aggregateID,
            outputDeviceUID: outputDeviceUID,
            tapRuntimes: tapRuntimes
        )

        let outputBufferIndices = Array(
            Set(tapRuntimes.flatMap { runtime in
                (0..<runtime.inputBufferCount).map { runtime.outputBufferOffset + $0 }
            })
        ).sorted()
        let audioConfigurations = tapRuntimes.map { runtime in
            var configuration = MacMixAudioTapConfiguration()
            configuration.format = runtime.format
            configuration.inputBufferOffset = UInt32(clamping: runtime.inputBufferOffset)
            configuration.inputBufferCount = UInt32(clamping: runtime.inputBufferCount)
            configuration.outputBufferOffset = UInt32(clamping: runtime.outputBufferOffset)
            configuration.initialGain = runtime.initialGain
            configuration.targetGain = runtime.targetGain
            return configuration
        }
        let cOutputBufferIndices = outputBufferIndices.map { UInt32(clamping: $0) }
        audioIOContext = audioConfigurations.withUnsafeBufferPointer { configurations in
            cOutputBufferIndices.withUnsafeBufferPointer { outputIndices in
                MacMixAudioIOContextCreate(
                    configurations.baseAddress!,
                    configurations.count,
                    outputIndices.baseAddress!,
                    outputIndices.count
                )
            }
        }

        guard let audioIOContext else {
            stopAfterInitializationFailure()
            return nil
        }

        gainStates = Dictionary(uniqueKeysWithValues: tapRuntimes.enumerated().map { index, runtime in
            (
                runtime.targetID,
                GainState(context: audioIOContext, configurationIndex: index)
            )
        })

        let status = AudioDeviceCreateIOProcID(
            aggregateID,
            MacMixAudioDeviceIOProc,
            audioIOContext,
            &ioProc
        )

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

        for index in tapIDs.indices where tapIDs[index] != kAudioObjectUnknown {
            if !Self.audioObjectExists(tapIDs[index]) {
                tapIDs[index] = kAudioObjectUnknown
            }
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

        if self.ioProc == nil, let audioIOContext {
            MacMixAudioIOContextDestroy(audioIOContext)
            self.audioIOContext = nil
        }

        if aggregateID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateID)
            if Self.didDestroy(status) || !Self.audioObjectExists(aggregateID) {
                aggregateID = kAudioObjectUnknown
            } else {
                return retiredAggregateID
            }
        }

        for index in tapIDs.indices where tapIDs[index] != kAudioObjectUnknown {
            let tapID = tapIDs[index]
            let status = AudioHardwareDestroyProcessTap(tapID)
            if Self.didDestroy(status) || !Self.audioObjectExists(tapID) {
                tapIDs[index] = kAudioObjectUnknown
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
        guard let deviceIDs = readHALAudioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        ) else {
            return nil
        }

        return Set(deviceIDs)
    }

    private static func graph(for targets: [AppMixTarget]) -> [String: [AudioObjectID]] {
        Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.audioObjectIDs) })
    }

    private static func setProcesses(
        _ audioObjectIDs: [AudioObjectID],
        on binding: TapBinding
    ) -> Bool {
        let previousAudioObjectIDs = binding.audioObjectIDs
        var address = propertyAddress(selector: kAudioTapPropertyDescription)
        var isSettable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(
            binding.tapID,
            &address,
            &isSettable
        )
        guard settableStatus == noErr, isSettable.boolValue else {
            diagnosticsLogger.error(
                "Tap description is not settable tap=\(binding.tapID) status=\(settableStatus)"
            )
            return false
        }

        let notification = DispatchSemaphore(value: 0)
        let listener: AudioObjectPropertyListenerBlock = { addressCount, addresses in
            for index in 0..<Int(addressCount) {
                if addresses[index].mSelector == kAudioTapPropertyDescription {
                    notification.signal()
                    return
                }
            }
        }
        let listenerStatus = AudioObjectAddPropertyListenerBlock(
            binding.tapID,
            &address,
            tapPropertyQueue,
            listener
        )
        guard listenerStatus == noErr else {
            diagnosticsLogger.error(
                "Failed to add tap description listener tap=\(binding.tapID) status=\(listenerStatus)"
            )
            return false
        }
        defer {
            var removalAddress = propertyAddress(selector: kAudioTapPropertyDescription)
            let removalStatus = AudioObjectRemovePropertyListenerBlock(
                binding.tapID,
                &removalAddress,
                tapPropertyQueue,
                listener
            )
            if !didDestroy(removalStatus) {
                diagnosticsLogger.error(
                    "Failed to remove tap description listener tap=\(binding.tapID) status=\(removalStatus)"
                )
            }
        }

        binding.description.processes = audioObjectIDs

        var description = Unmanaged.passUnretained(binding.description).toOpaque()
        let status = AudioObjectSetPropertyData(
            binding.tapID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UnsafeMutableRawPointer>.size),
            &description
        )

        guard status == noErr else {
            binding.description.processes = previousAudioObjectIDs
            diagnosticsLogger.error(
                "Failed to set tap processes tap=\(binding.tapID) status=\(status)"
            )
            return false
        }

        let timeout = DispatchTime.now() + tapDescriptionUpdateTimeout
        let notificationResult = notification.wait(timeout: timeout)
        guard let appliedDescription = tapDescription(for: binding.tapID) else {
            binding.description.processes = previousAudioObjectIDs
            diagnosticsLogger.error(
                "Failed to read back tap description tap=\(binding.tapID)"
            )
            return false
        }
        guard appliedDescription.processes == audioObjectIDs else {
            binding.description.processes = previousAudioObjectIDs
            diagnosticsLogger.error(
                "Tap process update was not applied tap=\(binding.tapID) requestedCount=\(audioObjectIDs.count) appliedCount=\(appliedDescription.processes.count)"
            )
            return false
        }
        if notificationResult != .success {
            // The listener notification is advisory here. A successful property
            // readback is the authoritative confirmation that HAL applied the change.
            diagnosticsLogger.notice(
                "Tap description listener timed out after successful readback tap=\(binding.tapID)"
            )
        }

        binding.audioObjectIDs = audioObjectIDs
        return true
    }

    private static func tapDescription(for tapID: AudioObjectID) -> CATapDescription? {
        var address = propertyAddress(selector: kAudioTapPropertyDescription)
        var description: Unmanaged<CATapDescription>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &dataSize,
            &description
        )

        guard status == noErr else {
            return nil
        }

        return description?.takeUnretainedValue()
    }

    private static func clampedGain(_ volume: Double) -> Float {
        Float(max(0, min(Double(AppAudioMixer.maximumGain), volume)))
    }

    private static func bufferCount(for format: AudioStreamBasicDescription) -> Int {
        let isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        return isNonInterleaved ? max(Int(format.mChannelsPerFrame), 1) : 1
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
        switch outputStreamSelection(outputDeviceUID: outputDeviceUID) {
        case let .stream(outputStreamIndex, outputBufferOffset):
            let outputStreamTap = Self.configure(
                CATapDescription(processes: audioObjectIDs, deviceUID: outputDeviceUID, stream: outputStreamIndex),
                name: "MacMix Output Stream \(outputStreamIndex)"
            )
            candidates = [
                ProcessTapConfiguration(
                    description: outputStreamTap,
                    outputBufferOffset: outputBufferOffset,
                    requiresDriftCompensation: false
                ),
            ]
        case .noStreams:
            candidates = [
                ProcessTapConfiguration(
                    description: stereoMixdownTap,
                    outputBufferOffset: 0,
                    requiresDriftCompensation: true
                ),
            ]
        case .failed:
            return nil
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
        if #available(macOS 26.0, *) {
            // Let HAL retain the app identity across process-object churn and restore
            // matching processes without requiring the aggregate device to be rebuilt.
            tapDescription.isProcessRestoreEnabled = true
        }
        return tapDescription
    }

    private static func outputStreamSelection(
        outputDeviceUID: String
    ) -> OutputStreamSelectionRead {
        guard let deviceIDs = audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        ), let deviceID = deviceIDs.first(where: { deviceID in
            stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
                == outputDeviceUID
        }), let candidates = outputStreamCandidates(deviceID: deviceID) else {
            return .failed
        }

        guard let selected = candidates.sorted(by: { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }

                if lhs.format.mChannelsPerFrame != rhs.format.mChannelsPerFrame {
                    return lhs.format.mChannelsPerFrame > rhs.format.mChannelsPerFrame
                }

                return lhs.index < rhs.index
            }).first else {
            return .noStreams
        }

        let outputBufferOffset = candidates
            .filter { $0.index < selected.index }
            .reduce(0) { offset, candidate in
                let isNonInterleaved = candidate.format.mFormatFlags
                    & kAudioFormatFlagIsNonInterleaved != 0
                return offset + (isNonInterleaved ? Int(candidate.format.mChannelsPerFrame) : 1)
            }
        return .stream(index: selected.index, outputBufferOffset: outputBufferOffset)
    }

    private static func outputStreamCandidates(deviceID: AudioObjectID) -> [OutputStreamCandidate]? {
        guard let streamIDs = audioObjectIDs(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        ) else {
            return nil
        }

        var candidates: [OutputStreamCandidate] = []
        candidates.reserveCapacity(streamIDs.count)
        for (streamIndex, streamID) in streamIDs.enumerated() {
            guard let format = streamFormat(streamID: streamID) else {
                return nil
            }

            candidates.append(OutputStreamCandidate(
                index: UInt(streamIndex),
                format: format,
                isActive: boolProperty(streamID, selector: kAudioStreamPropertyIsActive)
            ))
        }
        return candidates
    }

    private static func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID]? {
        readHALAudioObjectIDs(
            objectID: objectID,
            selector: selector,
            scope: scope
        )
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

    private static func logGraphDiagnostics(
        aggregateID: AudioObjectID,
        outputDeviceUID: String,
        tapRuntimes: [TapRuntime]
    ) {
        let taps = tapRuntimes.enumerated().map { index, runtime in
            "tap[\(index)]=\(formatDescription(runtime.format)) "
                + "inOffset=\(runtime.inputBufferOffset) "
                + "buffers=\(runtime.inputBufferCount) "
                + "outOffset=\(runtime.outputBufferOffset)"
        }.joined(separator: "; ")
        let inputStreams = streamDescriptions(
            deviceID: aggregateID,
            scope: kAudioDevicePropertyScopeInput
        )
        let outputStreams = streamDescriptions(
            deviceID: aggregateID,
            scope: kAudioDevicePropertyScopeOutput
        )
        let description = "Graph outputUID=\(outputDeviceUID); \(taps); "
            + "aggregate inputs=\(inputStreams); outputs=\(outputStreams)"
        diagnosticsLogger.notice("\(description, privacy: .public)")
    }

    private static func streamDescriptions(
        deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> String {
        guard let streamIDs = audioObjectIDs(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: scope
        ) else {
            return "unavailable"
        }

        return streamIDs.enumerated().map { index, streamID in
            guard let format = streamFormat(streamID: streamID) else {
                return "[\(index)]=?"
            }
            return "[\(index)]=\(formatDescription(format))"
        }
        .joined(separator: ", ")
    }

    private static func formatDescription(
        _ format: AudioStreamBasicDescription
    ) -> String {
        String(
            format: "%.0fHz id=%08x flags=%08x bpf=%u ch=%u bits=%u",
            format.mSampleRate,
            format.mFormatID,
            format.mFormatFlags,
            format.mBytesPerFrame,
            format.mChannelsPerFrame,
            format.mBitsPerChannel
        )
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

    private static func mixScaledAudio(
        from inputBuffer: AudioBuffer,
        into outputBuffer: AudioBuffer,
        gainRamp: GainRamp,
        format: AudioStreamBasicDescription
    ) -> Bool {
        guard let source = inputBuffer.mData,
              let destination = outputBuffer.mData,
              inputBuffer.mNumberChannels == outputBuffer.mNumberChannels else {
            return false
        }

        let byteCount = min(
            Int(inputBuffer.mDataByteSize),
            Int(outputBuffer.mDataByteSize)
        )
        guard byteCount > 0,
              format.mFormatID == kAudioFormatLinearPCM else {
            return false
        }

        let flags = format.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let channelCount = max(1, Int(inputBuffer.mNumberChannels))

        if isFloat {
            switch format.mBitsPerChannel {
            case 32:
                mixScaledFloat32(
                    from: source,
                    into: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            case 64:
                mixScaledFloat64(
                    from: source,
                    into: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            default:
                return false
            }
        } else if isSignedInteger {
            switch format.mBitsPerChannel {
            case 16:
                mixScaledInt16(
                    from: source,
                    into: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            case 24:
                return mixScaledInt24(
                    from: source,
                    into: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount,
                    format: format
                )
            case 32:
                mixScaledInt32(
                    from: source,
                    into: destination,
                    gainRamp: gainRamp,
                    channelCount: channelCount,
                    byteCount: byteCount
                )
            default:
                return false
            }
        } else {
            return false
        }

        return true
    }

    private static func mixScaledFloat32(
        from source: UnsafeMutableRawPointer,
        into destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            return
        }

        let source = source.assumingMemoryBound(to: Float.self)
        let destination = destination.assumingMemoryBound(to: Float.self)
        let channelCount = max(1, min(channelCount, sampleCount))
        let frameCount = sampleCount / channelCount
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)
        let rampSampleCount = rampFrameCount * channelCount
        let gainStep = rampFrameCount > 0
            ? (gainRamp.end - gainRamp.start) / Float(rampFrameCount)
            : 0

        for index in 0..<rampSampleCount {
            let gain = gainRamp.start + Float(index / channelCount) * gainStep
            destination[index] += source[index] * gain
        }

        mixRemainingSamples(
            from: source,
            into: destination,
            startIndex: rampSampleCount,
            sampleCount: sampleCount,
            gain: gainRamp.end
        )
    }

    private static func mixScaledFloat64(
        from source: UnsafeMutableRawPointer,
        into destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Double>.size
        guard sampleCount > 0 else {
            return
        }

        let source = source.assumingMemoryBound(to: Double.self)
        let destination = destination.assumingMemoryBound(to: Double.self)
        let channelCount = max(1, min(channelCount, sampleCount))
        let frameCount = sampleCount / channelCount
        let rampFrameCount = min(Int(gainRamp.frameCount), frameCount)
        let rampSampleCount = rampFrameCount * channelCount
        let startGain = Double(gainRamp.start)
        let gainStep = rampFrameCount > 0
            ? (Double(gainRamp.end) - startGain) / Double(rampFrameCount)
            : 0

        for index in 0..<rampSampleCount {
            let gain = startGain + Double(index / channelCount) * gainStep
            destination[index] += source[index] * gain
        }

        mixRemainingSamples(
            from: source,
            into: destination,
            startIndex: rampSampleCount,
            sampleCount: sampleCount,
            gain: Double(gainRamp.end)
        )
    }

    private static func mixRemainingSamples(
        from source: UnsafePointer<Float>,
        into destination: UnsafeMutablePointer<Float>,
        startIndex: Int,
        sampleCount: Int,
        gain: Float
    ) {
        guard startIndex < sampleCount, gain != 0 else {
            return
        }

        let count = vDSP_Length(sampleCount - startIndex)
        let source = source.advanced(by: startIndex)
        let destination = destination.advanced(by: startIndex)
        if gain == 1 {
            vDSP_vadd(source, 1, destination, 1, destination, 1, count)
        } else {
            var gain = gain
            vDSP_vsma(source, 1, &gain, destination, 1, destination, 1, count)
        }
    }

    private static func mixRemainingSamples(
        from source: UnsafePointer<Double>,
        into destination: UnsafeMutablePointer<Double>,
        startIndex: Int,
        sampleCount: Int,
        gain: Double
    ) {
        guard startIndex < sampleCount, gain != 0 else {
            return
        }

        let count = vDSP_Length(sampleCount - startIndex)
        let source = source.advanced(by: startIndex)
        let destination = destination.advanced(by: startIndex)
        if gain == 1 {
            vDSP_vaddD(source, 1, destination, 1, destination, 1, count)
        } else {
            var gain = gain
            vDSP_vsmaD(source, 1, &gain, destination, 1, destination, 1, count)
        }
    }

    private static func mixScaledInt16(
        from source: UnsafeMutableRawPointer,
        into destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int16>.size
        let source = source.assumingMemoryBound(to: Int16.self)
        let destination = destination.assumingMemoryBound(to: Int16.self)
        mixIntegerSamples(
            sampleCount: sampleCount,
            channelCount: channelCount,
            gainRamp: gainRamp
        ) { index, gain in
            let mixed = Double(destination[index]) + Double(source[index]) * Double(gain)
            destination[index] = Int16(clamping: Int(mixed.rounded()))
        }
    }

    private static func mixScaledInt32(
        from source: UnsafeMutableRawPointer,
        into destination: UnsafeMutableRawPointer,
        gainRamp: GainRamp,
        channelCount: Int,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int32>.size
        let source = source.assumingMemoryBound(to: Int32.self)
        let destination = destination.assumingMemoryBound(to: Int32.self)
        mixIntegerSamples(
            sampleCount: sampleCount,
            channelCount: channelCount,
            gainRamp: gainRamp
        ) { index, gain in
            let mixed = Double(destination[index]) + Double(source[index]) * Double(gain)
            destination[index] = Int32(clamping: Int64(mixed.rounded()))
        }
    }

    private static func mixIntegerSamples(
        sampleCount: Int,
        channelCount: Int,
        gainRamp: GainRamp,
        body: (Int, Float) -> Void
    ) {
        guard sampleCount > 0 else {
            return
        }

        let channelCount = max(1, min(channelCount, sampleCount))
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
            body(index, gain)
        }
    }

    private static func mixScaledInt24(
        from source: UnsafeMutableRawPointer,
        into destination: UnsafeMutableRawPointer,
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
        let source = source.assumingMemoryBound(to: UInt8.self)
        let destination = destination.assumingMemoryBound(to: UInt8.self)
        mixIntegerSamples(
            sampleCount: sampleCount,
            channelCount: channelCount,
            gainRamp: gainRamp
        ) { index, gain in
            let offset = index * bytesPerSample
            let sourceSample = readSignedInt24(
                from: source.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
            let destinationSample = readSignedInt24(
                from: destination.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
            let mixed = Double(destinationSample) + Double(sourceSample) * Double(gain)
            writeSignedInt24(
                clampInt24(mixed.rounded()),
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

}
