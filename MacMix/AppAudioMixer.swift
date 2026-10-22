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
import MacMixStudio

nonisolated struct AppMixTarget: Sendable, Equatable {
    let id: String
    let audioObjectIDs: [AudioObjectID]
    let volume: Double
    var equalizerGains: [Double]? = nil
    var equalizerToneGains: [Double]? = nil
    // EQ readiness is independent of filtering and visible spectrum subscriptions.
    var keepsEqualizerWarm = false
    // nil follows the system; [] keeps the tap muted while selected devices are offline.
    var outputDeviceUIDs: [String]? = nil
    var airPlayRoutes: [String: AirPlayOutputRoute] = [:]
    var requiresProcessing: Bool { abs(volume - 1) >= 0.005 || equalizerGains != nil || outputDeviceUIDs != nil || keepsEqualizerWarm }
    // Processing this target sounds identical to the app's native output.
    var isSoundNeutralWarm: Bool {
        keepsEqualizerWarm && abs(volume - 1) < 0.005 && equalizerGains == nil && outputDeviceUIDs == nil
    }
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

    var equalizerParametersOnly = false

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
    case deferred
}

nonisolated final class AppAudioMixer: @unchecked Sendable {
    static let shared = AppAudioMixer()
    fileprivate static let maximumGain: Float = 2
    private static let maximumGainHandoffDuration: TimeInterval = 0.12
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
    private final class MemberOutputRecovery {
        var budget = OutputRecoveryBudget()
        var health: OutputRouteHealth?
        var monitor: OutputRouteHealthMonitor?
        var generation: UInt64 = 0
        var lastDeferral: String?
        var invalidated = false
        var stall = OutputStallDetector()
        var stallLimiter = OutputStallLimiter()
        var verifiesRender = false
    }
    private var memberOutputRecovery: [String: MemberOutputRecovery] = [:]
    // Process output state from the latest reconciliation; HAL reads stay on this queue.
    private var outputtingTargets: Set<String> = []
    private var lastOutputAt: [String: TimeInterval] = [:]
    private var admittedTargetIDs: Set<String> = []
    // Explicit routes stay muted while their member is unavailable or rebuilding.
    private var memberRouteMuteGuards: [String: ProcessTapMuteGuard] = [:]
    private var memberRouteGuardObjects: [String: [AudioObjectID]] = [:]
    private var pendingMemberRouteGuards: [ProcessTapMuteGuard] = []
    private var engine: (any AppGainEngine)?
    private var pendingRetirements: [AppGainEngineRetirement] = []
    private var outputSwitchMuteGuard: ProcessTapMuteGuard?
    private var routingMuteGuard: ProcessTapMuteGuard?
    private var routingGuardObjects: [AudioObjectID] = []
    private let latestCommandRevision = ManagedAtomic<UInt64>(0)
    private let diagnosticSnapshotPending = ManagedAtomic<Bool>(false)
    private let routingGraphActive = ManagedAtomic<Bool>(false)
    var requiresRoutingValidation: Bool { routingGraphActive.load(ordering: .acquiring) }
    private var latestRouteCommand: AppMixerCommand?
    private var meterSubscriptions: [String: Set<UUID>] = [:]
    private var cachedSpectra: [String: (values: [Float], time: UInt64)] = [:]

    func setMetering(_ enabled: Bool, for targetID: String, subscription: UUID) {
        lifecycleQueue.async { [self] in
            let wasActive = meterSubscriptions[targetID]?.isEmpty == false
            if enabled { meterSubscriptions[targetID, default: []].insert(subscription) }
            else {
                meterSubscriptions[targetID]?.remove(subscription)
                if meterSubscriptions[targetID]?.isEmpty == true { meterSubscriptions.removeValue(forKey: targetID) }
            }
            let active = meterSubscriptions[targetID]?.isEmpty == false
            engine?.setMetering(active, for: targetID)
            if !active { cachedSpectra.removeValue(forKey: targetID) }
            // A visible spectrum also needs a unity/bypassed tap when EQ is off.
            // Reuse the serialized mixer lifecycle and never revive a stale route.
            if active != wasActive, let command = latestRouteCommand, isCurrent(command) {
                _ = reconcileWithOutputHealth(command)
            }
        }
    }

    func spectrum(for targetID: String) async -> [Float] {
        await withCheckedContinuation { continuation in
            lifecycleQueue.async { [self] in
                guard meterSubscriptions[targetID]?.isEmpty == false else {
                    continuation.resume(returning: [])
                    return
                }
                let now = DispatchTime.now().uptimeNanoseconds
                if let values = engine?.spectrum(for: targetID) {
                    cachedSpectra[targetID] = (values, now)
                    continuation.resume(returning: values)
                } else if let cached = cachedSpectra[targetID], now &- cached.time < 150_000_000 {
                    continuation.resume(returning: cached.values)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func applyMeterSubscriptions() {
        for targetID in meterSubscriptions.keys { engine?.setMetering(true, for: targetID) }
    }

    /// Snapshot on the lifecycle queue; never dereference an IO context after teardown.
    func requestDiagnosticSnapshot(diagnosticID: String) {
        guard diagnosticSnapshotPending.compareExchange(expected: false, desired: true,
            ordering: .acquiringAndReleasing).exchanged else { return }
        let queuedAt = DispatchTime.now().uptimeNanoseconds
        lifecycleQueue.async { [self] in
            defer { diagnosticSnapshotPending.store(false, ordering: .releasing) }
            var fields = ["diagnostic": diagnosticID, "active": String(engine != nil),
                "pendingRetirements": String(pendingRetirements.count),
                "queueDelayMs": String((DispatchTime.now().uptimeNanoseconds - queuedAt) / 1_000_000)]
            if let group = engine as? AppGainEngineGroup {
                fields["graphCount"] = String(group.members.count)
                for (id, graph) in group.members {
                    DiagnosticLog.shared.record("performance", "graph_progress", fields: [
                        "diagnostic": diagnosticID, "appInstance": DiagnosticLog.shared.anonymous(id),
                        "aggregates": graph.aggregateDeviceIDs.map(String.init).joined(separator: ","),
                        "renderedFrames": String(graph.renderedFrames)])
                }
            }
            DiagnosticLog.shared.record("performance", "mixer_snapshot", fields: fields)
        }
    }

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
            let began = DispatchTime.now().uptimeNanoseconds
            let result = reconcile(command)
            recordCommandResult(command, result: result, began: began, phase: "reconcile")
            completion(result)
        }
    }

    func submitTransition(
        _ command: AppMixerCommand,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            let began = DispatchTime.now().uptimeNanoseconds
            let result = transition(command)
            recordCommandResult(command, result: result, began: began, phase: "transition")
            completion(result)
        }
    }

    func submitTransitionCompletingOutputSwitch(
        _ command: AppMixerCommand,
        completion: @escaping @Sendable (AppMixerResult) -> Void
    ) {
        lifecycleQueue.async { [self] in
            let began = DispatchTime.now().uptimeNanoseconds
            let result = transition(command)
            recordCommandResult(command, result: result, began: began, phase: "output_switch_transition")
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
            DiagnosticLog.shared.record("mixer", "output_quiesce_started", fields: ["revision": String(revision)])
            let engineToRetire = engine
            let guardedAudioObjectIDs = Set(
                (engineToRetire?.tappedObjects ?? [])
                    + targets
                        .filter { $0.requiresProcessing }
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

    private func recordCommandResult(_ command: AppMixerCommand, result: AppMixerResult, began: UInt64, phase: String) {
        let elapsed = (DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
        DiagnosticCounters.shared.increment("mixer_commands")
        DiagnosticCounters.shared.increment("mixer_command_ms", by: elapsed)
        if result != .applied || elapsed > 100 || phase != "reconcile" {
            let outcome = switch result {
            case .applied: "applied"
            case .failed: "failed"
            case .superseded: "superseded"
            case .deferred: "deferred"
            }
            DiagnosticLog.shared.record("mixer", "command_result", level: result == .failed ? "error" : "info", fields: [
                "phase": phase, "revision": String(command.revision), "routeGeneration": String(command.routeGeneration),
                "result": outcome, "durationMs": String(elapsed), "targetCount": String(command.targets.count)])
        }
    }

    private func reconcile(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command) else {
            return .superseded
        }

        latestRouteCommand = command
        return reconcileWithOutputHealth(command)
    }

    private func transition(_ command: AppMixerCommand) -> AppMixerResult {
        guard isCurrent(command) else {
            return .superseded
        }

        latestRouteCommand = command
        return reconcileWithOutputHealth(command)
    }

    private func reconcileWithOutputHealth(_ command: AppMixerCommand) -> AppMixerResult {
        let processing = admittedTargets(command.targets)
        admittedTargetIDs = Set(processing.map(\.id))
        var targets = command.targets
        if !processing.isEmpty, let uid = command.outputDeviceUID {
            let uids = Set(processing.flatMap { $0.outputDeviceUIDs ?? [uid] }).sorted()
            let sharedHealth = OutputRouteHealth.read(uids: uids)
            guard isCurrent(command) else { return .superseded }
            for target in processing {
                let health = sharedHealth.selecting(target.outputDeviceUIDs ?? [uid])
                guard isCurrent(command) else { return .superseded }
                let state = memberOutputRecovery[target.id] ?? MemberOutputRecovery()
                let initialHealthy = state.health == nil && state.budget.key.isEmpty && health.ready
                let notified = (state.monitor?.revision.load(ordering: .relaxed) ?? 0) != 0
                let changedExistingDevice = state.health?.deviceSignatures.contains { entry in
                    health.deviceSignatures[entry.key].map { $0 != entry.value } == true
                } ?? false
                // Compare only shared devices: a user adding/removing a healthy
                // destination still uses the existing overlap replacement path.
                let invalidated = notified || changedExistingDevice
                if state.health != health || invalidated {
                    DiagnosticLog.shared.record("route", "output_health_changed", fields: [
                        "appInstance": DiagnosticLog.shared.anonymous(target.id),
                        "reason": state.health?.deviceIDs != health.deviceIDs ? "device_instance" :
                            (state.health?.objects != health.objects ? "stream_set" : "stream_format_or_availability"),
                        "objects": health.objects.map(String.init).joined(separator: ","),
                        "ready": String(health.ready), "revision": String(command.revision)])
                    state.invalidated = state.invalidated || invalidated || !health.ready
                    state.health = health
                    state.monitor = OutputRouteHealthMonitor(objects: health.objects)
                    state.generation &+= 1
                }
                let key = health.signature + ":event=\(state.generation):objects="
                    + target.audioObjectIDs.sorted().map(String.init).joined(separator: ",")
                state.budget.observe(key, now: ProcessInfo.processInfo.systemUptime, waitForStability: !initialHealthy)
                memberOutputRecovery[target.id] = state
                if let selected = target.outputDeviceUIDs, let index = targets.firstIndex(where: { $0.id == target.id }) {
                    // Keep healthy destinations of this app; [] remains an explicit
                    // silent route and is never changed into follow-system (nil).
                    targets[index].outputDeviceUIDs = selected.filter { health.readyDeviceUIDs.contains($0) }
                }
            }
        }
        let result = reconcileCurrentRoute(command, targets: targets)
        guard isCurrent(command) else { releaseSupersededGuards(); return .superseded }
        if result == .failed {
            releaseOutputSwitchMuteGuard()
            releaseRoutingMuteGuard()
        }
        return result
    }

    private func admittedTargets(_ targets: [AppMixTarget]) -> [AppMixTarget] {
        let now = ProcessInfo.processInfo.systemUptime
        let candidates = targets.filter { $0.requiresProcessing || meterSubscriptions[$0.id]?.isEmpty == false }
        let candidateIDs = Set(candidates.map(\.id))
        outputtingTargets = readOutputtingTargets(candidates)
        lastOutputAt = lastOutputAt.filter { candidateIDs.contains($0.key) }
        for id in outputtingTargets { lastOutputAt[id] = now }
        let group = engine as? AppGainEngineGroup
        return candidates.filter { target in
            let hasMember = group?.members[target.id] != nil
            let admitted = WarmGraphPolicy.admits(soundNeutral: target.isSoundNeutralWarm,
                metering: meterSubscriptions[target.id]?.isEmpty == false, hasMember: hasMember,
                outputting: outputtingTargets.contains(target.id), lastOutputAt: lastOutputAt[target.id], now: now)
            if hasMember, !admitted {
                DiagnosticLog.shared.record("mixer", "warm_graph_released", fields: [
                    "appInstance": DiagnosticLog.shared.anonymous(target.id), "reason": "idle"])
            }
            return admitted
        }
    }

    // A newer revision is queued behind this one and reconciles from the graphs
    // built so far. Retiring the whole group here would restart every playing
    // app on each superseded edit, e.g. while dragging an idle app's slider.
    private func releaseSupersededGuards() {
        // Fail open to native playback instead of leaving a mute-only tap behind.
        releaseOutputSwitchMuteGuard()
        releaseRoutingMuteGuard()
    }

    private func reconcileCurrentRoute(_ command: AppMixerCommand, targets requestedTargets: [AppMixTarget]) -> AppMixerResult {
        pendingRetirements.removeAll(where: \.isComplete)
        defer { routingGraphActive.store(engine?.keepsRoutingPath == true, ordering: .releasing) }
        guard isCurrent(command) else { return .failed }
        var targets = requestedTargets.filter { !$0.audioObjectIDs.isEmpty }
        // Confirm again on the serialized lifecycle queue, not only in the UI
        // snapshot. A changed receiver is an offline destination, never fallback.
        targets = targets.map { target in
            var target = target
            if let uids = target.outputDeviceUIDs {
                target.outputDeviceUIDs = AirPlayOutputRoute.validatedUIDs(uids, routes: target.airPlayRoutes)
            }
            return target
        }
        if engine == nil, let systemUID = command.outputDeviceUID {
            targets = targets.map { target in
                var processingTarget = target
                if target.airPlayRoutes.isEmpty, let selected = target.outputDeviceUIDs,
                   RoutedAudioLayout.canKeepNativeOutput(processIDs: target.audioObjectIDs,
                       selectedUIDs: selected, systemUID: systemUID) {
                    processingTarget.outputDeviceUIDs = nil
                }
                return processingTarget
            }
        }
        let activeTargets = targets.filter { admittedTargetIDs.contains($0.id) }
        guard !activeTargets.isEmpty else {
            if let old = engine {
                engine = nil
                prepareForUnityHandoff(old)
                enqueueRetirement(old)
                guard waitForPendingAggregateRemoval(command: command) else { return .failed }
            }
            cleanupMemberRecovery(activeIDs: [])
            return releaseRoutingMuteGuard() ? .applied : .failed
        }
        guard Self.isSupported, let outputDeviceUID = command.outputDeviceUID else { return .failed }
        if let old = engine, old.outputDeviceUID != outputDeviceUID {
            guard protectRoutingProcesses(old.tappedObjects) else { return .failed }
            engine = nil
            enqueueRetirement(old)
            guard waitForPendingAggregateRemoval(command: command), isCurrent(command) else { return .failed }
        }
        guard waitForPendingAggregateRemoval(command: command), isCurrent(command) else { return .failed }
        let group = (engine as? AppGainEngineGroup) ?? AppGainEngineGroup(outputDeviceUID: outputDeviceUID)
        engine = group
        let activeIDs = Set(activeTargets.map(\.id))
        for (id, member) in group.members where !activeIDs.contains(id) {
            group.members.removeValue(forKey: id)
            cachedSpectra.removeValue(forKey: id)
            // Only this app leaves the graph; other apps keep their IO callbacks.
            prepareForUnityHandoff(member)
            enqueueRetirement(member)
        }
        cleanupMemberRecovery(activeIDs: activeIDs)
        var deferred = false
        var failed = false
        for target in activeTargets {
            guard isCurrent(command) else { return .superseded }
            let state = memberOutputRecovery[target.id] ?? MemberOutputRecovery()
            if target.outputDeviceUIDs != nil,
               (state.invalidated || group.members[target.id] == nil) {
                guard protectMemberRoute(target) else { failed = true; continue }
            }
            if state.invalidated {
                retireMember(target.id, group: group)
                state.invalidated = false
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let member = group.members[target.id], let aggregate = member.aggregateDeviceIDs.first,
               let reason = state.stall.observe(graph: aggregate, frames: member.renderedFrames,
                   outputting: outputtingTargets.contains(target.id),
                   // A silent offline route has no physical output and never renders.
                   deviceReady: !member.physicalOutputUIDs.isEmpty
                       && Set(member.physicalOutputUIDs).isSubset(of: state.health?.readyDeviceUIDs ?? []),
                   subdevicesActive: member.hasActiveOutputSubdevices, now: now) {
                let rebuilds = state.stallLimiter.canRebuild(now: now)
                DiagnosticLog.shared.record("mixer", "output_stall_detected", level: "error", fields: [
                    "appInstance": DiagnosticLog.shared.anonymous(target.id), "reason": reason,
                    "aggregate": String(aggregate), "stalledMs": String(Int(state.stall.stalledFor(now: now) * 1000)),
                    "explicitRoute": String(target.outputDeviceUIDs != nil), "rebuild": String(rebuilds)])
                // Explicit routes keep the app muted; following the system fails open.
                if target.outputDeviceUIDs != nil {
                    guard protectMemberRoute(target) else { failed = true; continue }
                }
                retireMember(target.id, group: group)
                if rebuilds {
                    state.stallLimiter.began(now: now)
                    state.verifiesRender = true
                } else {
                    state.stallLimiter.exhaust(now: now)
                    DiagnosticLog.shared.record("mixer", target.outputDeviceUIDs == nil ? "output_stall_failopen" : "output_stall_muted",
                        level: "error", fields: ["appInstance": DiagnosticLog.shared.anonymous(target.id),
                            "retryInMs": String(Int((state.stallLimiter.holdUntil - now) * 1000))])
                }
            }
            if group.members[target.id] == nil, state.stallLimiter.isHolding(now: now) {
                if state.lastDeferral != "stall_backoff" {
                    DiagnosticLog.shared.record("mixer", "output_recovery_deferred", fields: [
                        "appInstance": DiagnosticLog.shared.anonymous(target.id),
                        "reason": "stall_backoff", "attempts": String(state.stallLimiter.attempts.count)])
                    state.lastDeferral = "stall_backoff"
                }
                deferred = true
                continue
            }
            if group.members[target.id] == nil {
                let ready = target.outputDeviceUIDs != nil || state.health?.ready == true
                guard !SharedProcessTapGainEngine.isInitializationCleanupPending,
                      state.budget.canAttempt(ready: ready, now: ProcessInfo.processInfo.systemUptime) else {
                    let reason = !ready ? "output_unavailable" :
                        (SharedProcessTapGainEngine.isInitializationCleanupPending ? "cleanup_pending" :
                            (state.budget.failures >= 4 ? "retry_exhausted" : "stability_or_backoff"))
                    if state.lastDeferral != reason {
                        DiagnosticLog.shared.record("mixer", "output_recovery_deferred", fields: [
                            "appInstance": DiagnosticLog.shared.anonymous(target.id),
                            "reason": reason, "attempts": String(state.budget.failures)])
                        state.lastDeferral = reason
                    }
                    deferred = true
                    continue
                }
            }
            state.lastDeferral = nil
            if !reconcileMember(target, group: group, command: command) {
                guard isCurrent(command) else { return .superseded }
                state.budget.failed(now: ProcessInfo.processInfo.systemUptime)
                DiagnosticLog.shared.record("mixer", "output_rebuild_failed", level: "error", fields: [
                    "appInstance": DiagnosticLog.shared.anonymous(target.id),
                    "attempt": String(state.budget.failures), "revision": String(command.revision)])
                // A failed member must never take healthy members down with it.
                if target.outputDeviceUIDs == nil || protectMemberRoute(target) {
                    retireMember(target.id, group: group)
                }
                deferred = true
                continue
            }
            if state.verifiesRender {
                state.verifiesRender = false
                let began = ProcessInfo.processInfo.systemUptime
                if let member = group.members[target.id], waitForRender(member, command: command) {
                    state.stallLimiter.succeeded()
                    DiagnosticLog.shared.record("mixer", "output_stall_recovered", fields: [
                        "appInstance": DiagnosticLog.shared.anonymous(target.id),
                        "verifyMs": String(Int((ProcessInfo.processInfo.systemUptime - began) * 1000))])
                } else {
                    guard isCurrent(command) else { return .superseded }
                    state.stallLimiter.failed(now: ProcessInfo.processInfo.systemUptime)
                    DiagnosticLog.shared.record("mixer", "output_stall_rebuild_silent", level: "error", fields: [
                        "appInstance": DiagnosticLog.shared.anonymous(target.id),
                        "attempts": String(state.stallLimiter.attempts.count)])
                    if target.outputDeviceUIDs == nil || protectMemberRoute(target) {
                        retireMember(target.id, group: group)
                    }
                    deferred = true
                    continue
                }
            }
            _ = releaseMemberRouteGuard(target.id)
        }
        applyMeterSubscriptions()
        if group.members.isEmpty { engine = nil }
        releaseOutputSwitchMuteGuard()
        if !releaseRoutingMuteGuard() { failed = true }
        if failed { return .failed }
        if deferred { return probeSystemAudioPermission() ? .deferred : .failed }
        return .applied
    }

    private func reconcileMember(_ target: AppMixTarget, group: AppGainEngineGroup, command: AppMixerCommand) -> Bool {
        guard isCurrent(command) else { return false }
        if let current = group.members[target.id] {
            current.silenceChangedAirPlayReceivers()
            if !current.updateGraphIfPossible([target], validatesFormat: !command.equalizerParametersOnly) {
                if current.canOverlapRoutingReplacement {
                    guard let replacement = replacementRoutingGraphWhilePlaying(current,
                        targets: [target], command: command) else { return false }
                    group.members[target.id] = replacement
                } else {
                    guard rebuildMember(target, current: current, group: group, command: command) else { return false }
                }
            }
        } else {
            if target.outputDeviceUIDs?.isEmpty == true {
                guard protectRoutingProcesses(target.audioObjectIDs) else { return false }
            }
            // A new app gets its own tap/aggregate. Never rebuild a playing
            // app's graph merely to append a new input stream.
            guard let added = SharedProcessTapGainEngine(targets: [target],
                startsAtTargetGain: true, outputDeviceUID: group.outputDeviceUID) else { return false }
            group.members[target.id] = added
        }
        group.setGain(clampedGain(target.volume), for: target.id)
        group.setEqualizer(target.equalizerGains, toneGains: target.equalizerToneGains, for: target.id)
        return isCurrent(command)
    }

    private func retireMember(_ id: String, group: AppGainEngineGroup) {
        if let old = group.members.removeValue(forKey: id) { enqueueRetirement(old) }
        cachedSpectra.removeValue(forKey: id)
    }

    private func protectMemberRoute(_ target: AppMixTarget) -> Bool {
        let objects = Set(target.audioObjectIDs).sorted()
        if objects == memberRouteGuardObjects[target.id], memberRouteMuteGuards[target.id] != nil { return true }
        guard let next = ProcessTapMuteGuard(audioObjectIDs: objects) else { return false }
        guard releaseMemberRouteGuard(target.id) else {
            // Retain ownership if HAL has not stopped the replacement guard either.
            next.stop()
            if !next.isStopped { pendingMemberRouteGuards.append(next) }
            return false
        }
        memberRouteMuteGuards[target.id] = next
        memberRouteGuardObjects[target.id] = objects
        return true
    }

    @discardableResult
    private func releaseMemberRouteGuard(_ id: String) -> Bool {
        guard let guardTap = memberRouteMuteGuards[id] else { return true }
        guardTap.stop()
        guard guardTap.isStopped else { return false }
        memberRouteMuteGuards.removeValue(forKey: id)
        memberRouteGuardObjects.removeValue(forKey: id)
        return true
    }

    private func cleanupMemberRecovery(activeIDs: Set<String>) {
        for id in Array(memberOutputRecovery.keys) where !activeIDs.contains(id) {
            memberOutputRecovery.removeValue(forKey: id)
        }
        for id in Array(memberRouteMuteGuards.keys) where !activeIDs.contains(id) {
            _ = releaseMemberRouteGuard(id)
        }
        pendingMemberRouteGuards.removeAll { guardTap in
            guardTap.stop()
            return guardTap.isStopped
        }
    }

    private func protectRoutingProcesses(_ objects: [AudioObjectID]) -> Bool {
        let requested = Set(objects + routingGuardObjects).sorted()
        guard !requested.isEmpty, requested != routingGuardObjects else { return true }
        guard let next = ProcessTapMuteGuard(audioObjectIDs: requested) else { return false }
        guard releaseRoutingMuteGuard() else { next.stop(); return false }
        routingMuteGuard = next
        routingGuardObjects = requested
        return true
    }

    private func rebuildMember(_ target: AppMixTarget, current: SharedProcessTapGainEngine,
                               group: AppGainEngineGroup, command: AppMixerCommand) -> Bool {
        guard protectRoutingProcesses(current.tappedObjects + target.audioObjectIDs) else { return false }
        group.members.removeValue(forKey: target.id)
        enqueueRetirement(current)
        guard waitForPendingAggregateRemoval(command: command), isCurrent(command),
              let replacement = SharedProcessTapGainEngine(targets: [target], startsAtTargetGain: true,
                  outputDeviceUID: group.outputDeviceUID) else { return false }
        group.members[target.id] = replacement
        return true
    }

    /// Keep the current graph rendering while the replacement opens its devices
    /// and warms its own filters. Device-set edits must not use the stop/start path.
    private func replacementRoutingGraphWhilePlaying(
        _ current: SharedProcessTapGainEngine,
        targets: [AppMixTarget], command: AppMixerCommand
    ) -> SharedProcessTapGainEngine? {
        guard let replacement = SharedProcessTapGainEngine(targets: targets,
            startsAtTargetGain: true, outputDeviceUID: current.outputDeviceUID,
            initialOutputGain: 0, preferredClockUID: current.primaryRoutedDeviceUID) else { return nil }

        let beganWarmup = Date()
        let warmupDeadline = beganWarmup.addingTimeInterval(1)
        while Date() < warmupDeadline, isCurrent(command) {
            // The real callback must have run, not merely AudioDeviceStart. Give
            // Bluetooth outputs time to prime without silencing existing devices.
            if replacement.renderedFrames >= 4096,
               Date().timeIntervalSince(beganWarmup) >= 0.3 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard isCurrent(command), replacement.renderedFrames >= 4096 else {
            enqueueRetirement(replacement) // Still silent; current graph is untouched.
            return nil
        }

        // Linear complementary ramps keep correlated audio on a shared device at
        // unity. Fading app gain before its limiter would change the EQ sound.
        // Independent frame counters can be a buffer apart and briefly sum above
        // unity. Both envelopes now refer to the same output host-time interval.
        let fadeStart = MacMixAudioOutputFadeStartTime(0.1)
        current.scheduleOutputGain(from: 1, to: 0, start: fadeStart)
        replacement.scheduleOutputGain(from: 0, to: 1, start: fadeStart)
        let earliestRetirement = DispatchTime.now().uptimeNanoseconds + 160_000_000
        let fadeDeadline = Date().addingTimeInterval(0.5)
        while Date() < fadeDeadline {
            if replacement.renderedOutputGain >= 0.999, current.renderedOutputGain <= 0.001,
               DispatchTime.now().uptimeNanoseconds >= earliestRetirement { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard replacement.renderedOutputGain >= 0.999, current.renderedOutputGain <= 0.001 else {
            current.setOutputGain(1)
            replacement.setOutputGain(0)
            let restoreDeadline = Date().addingTimeInterval(0.15)
            while Date() < restoreDeadline, current.renderedOutputGain < 0.999 {
                Thread.sleep(forTimeInterval: 0.005)
            }
            enqueueRetirement(replacement)
            return nil
        }

        // Complete an already-started fade even if a newer request arrived. The
        // queued command will then build from this live graph, with no silent gap.
        enqueueRetirement(current)
        return replacement
    }

    private func stopAllNow() {
        routingGraphActive.store(false, ordering: .releasing)
        latestRouteCommand = nil
        cleanupMemberRecovery(activeIDs: [])
        meterSubscriptions.removeAll()
        cachedSpectra.removeAll()
        releaseOutputSwitchMuteGuard()
        releaseRoutingMuteGuard()
        if let engine {
            enqueueRetirement(engine)
        }

        engine = nil
        _ = waitForPendingAggregateRemoval()
    }

    private func readOutputtingTargets(_ targets: [AppMixTarget]) -> Set<String> {
        Set(targets.filter { target in
            target.audioObjectIDs.contains {
                OutputRouteHealth.uintProperty($0, kAudioProcessPropertyIsRunningOutput) == 1
            }
        }.map(\.id))
    }

    /// A rebuilt graph counts only after its real IO callback has rendered.
    private func waitForRender(_ member: SharedProcessTapGainEngine, command: AppMixerCommand) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < deadline, isCurrent(command) {
            if member.renderedFrames >= 4096 { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return member.renderedFrames >= 4096 && isCurrent(command)
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
        DiagnosticLog.shared.record("mixer", "output_switch_mute_guard_release",
            level: self.outputSwitchMuteGuard == nil ? "info" : "error",
            fields: ["released": String(self.outputSwitchMuteGuard == nil)])
    }

    @discardableResult
    private func releaseRoutingMuteGuard() -> Bool {
        let hadGuard = routingMuteGuard != nil
        let deadline = Date().addingTimeInterval(0.8)
        while routingMuteGuard?.isStopped == false, Date() < deadline {
            routingMuteGuard?.stop()
            if routingMuteGuard?.isStopped == false { Thread.sleep(forTimeInterval: 0.02) }
        }
        if routingMuteGuard?.isStopped != false {
            routingMuteGuard = nil
            routingGuardObjects = []
        }
        if hadGuard {
            DiagnosticLog.shared.record("mixer", "routing_mute_guard_release",
                level: routingMuteGuard == nil ? "info" : "error",
                fields: ["released": String(routingMuteGuard == nil)])
        }
        return routingMuteGuard == nil
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
        DiagnosticLog.shared.record("mixer", "graph_retirement_queued", fields: [
            "aggregates": engine.aggregateDeviceIDs.map(String.init).joined(separator: ",")])
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
    nonisolated var keepsRoutingPath: Bool { get }
    nonisolated var aggregateDeviceIDs: [AudioObjectID] { get }
    nonisolated func containsTarget(_ targetID: String) -> Bool
    nonisolated func updateGraphIfPossible(_ targets: [AppMixTarget], validatesFormat: Bool) -> Bool
    nonisolated func setGain(_ gain: Float, for targetID: String)
    nonisolated func setAllGains(_ gain: Float)
    nonisolated func setEqualizer(_ gains: [Double]?, toneGains: [Double]?, for targetID: String)
    nonisolated func setMetering(_ enabled: Bool, for targetID: String)
    nonisolated func spectrum(for targetID: String) -> [Float]?
    nonisolated func hasRenderedAllGains(_ gain: Float) -> Bool

    @discardableResult
    nonisolated func stop() -> AudioObjectID?
}

/// Lifecycle membership changes independently from each app's realtime graph.
nonisolated private final class AppGainEngineGroup: AppGainEngine {
    let outputDeviceUID: String
    var members: [String: SharedProcessTapGainEngine] = [:]
    init(outputDeviceUID: String) { self.outputDeviceUID = outputDeviceUID }
    var tappedObjects: [AudioObjectID] { members.values.flatMap(\.tappedObjects) }
    var aggregateDeviceIDs: [AudioObjectID] { members.values.flatMap(\.aggregateDeviceIDs) }
    var keepsRoutingPath: Bool { members.values.contains { $0.keepsRoutingPath } }
    var isStopped: Bool { members.values.allSatisfy(\.isStopped) }
    func containsTarget(_ id: String) -> Bool { members[id] != nil }
    func updateGraphIfPossible(_ targets: [AppMixTarget], validatesFormat: Bool) -> Bool {
        targets.allSatisfy { members[$0.id]?.updateGraphIfPossible([$0], validatesFormat: validatesFormat) == true }
    }
    func setGain(_ gain: Float, for id: String) { members[id]?.setGain(gain, for: id) }
    func setAllGains(_ gain: Float) { for member in members.values { member.setAllGains(gain) } }
    func setEqualizer(_ gains: [Double]?, toneGains: [Double]?, for id: String) {
        members[id]?.setEqualizer(gains, toneGains: toneGains, for: id)
    }
    func setMetering(_ enabled: Bool, for id: String) { members[id]?.setMetering(enabled, for: id) }
    func spectrum(for id: String) -> [Float]? { members[id]?.spectrum(for: id) }
    func hasRenderedAllGains(_ gain: Float) -> Bool { members.values.allSatisfy { $0.hasRenderedAllGains(gain) } }
    @discardableResult func stop() -> AudioObjectID? {
        var first: AudioObjectID?
        for member in members.values {
            if let id = member.stop(), first == nil { first = id }
        }
        return first
    }
}

nonisolated private final class AppGainEngineRetirement: @unchecked Sendable {
    private static let maximumCoordinationWaitNanoseconds: UInt64 = 750_000_000
    private let engine: any AppGainEngine
    private let teardownCompletedAt = ManagedAtomic<UInt64>(0)
    private let completed = ManagedAtomic<Bool>(false)
    private let completion: (@Sendable () -> Void)?

    init(engine: any AppGainEngine, completion: (@Sendable () -> Void)? = nil) {
        self.engine = engine
        self.completion = completion
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
            var retiredAggregateIDs = Set(engine.aggregateDeviceIDs)
            while !engine.isStopped {
                if let aggregateID = engine.stop() {
                    retiredAggregateIDs.insert(aggregateID)
                }

                if !engine.isStopped {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            DiagnosticLog.shared.record("mixer", "graph_teardown_finished", fields: [
                "aggregates": retiredAggregateIDs.sorted().map(String.init).joined(separator: ",")])
            teardownCompletedAt.store(DispatchTime.now().uptimeNanoseconds, ordering: .releasing)

            if !retiredAggregateIDs.isEmpty {
                while true {
                    if let activeDeviceIDs = Self.activeAudioDeviceIDs(),
                       activeDeviceIDs.isDisjoint(with: retiredAggregateIDs) {
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.02)
                }
            }

            completed.store(true, ordering: .releasing)
            completion?()
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
    let format: AudioStreamBasicDescription
    var supportsEqualizer: Bool {
        equalizer != nil
    }
    private var equalizer: UnsafeMutableRawPointer?
    private var currentEqualizerGains: [Double]?
    private var currentToneGains: [Double]?

    init(context: MacMixAudioIOContextRef, configurationIndex: Int, format: AudioStreamBasicDescription) {
        self.context = context
        self.configurationIndex = configurationIndex
        self.format = format
        MacMixAudioIOContextRetain(context)
        equalizer = MacMixEQCreate(format.mSampleRate, format.mChannelsPerFrame)
        if let equalizer {
            MacMixAudioIOContextSetEffect(context, configurationIndex, equalizer,
                MacMixEQBeginBlock, nil, MacMixEQDestroy)
            MacMixAudioIOContextSetFrameEffect(context, configurationIndex, MacMixEQProcessFrame)
            MacMixAudioIOContextSetMeter(context, configurationIndex,
                MacMixEQMeteringIsActive, MacMixEQObserveSample, MacMixEQEndBlock)
        }
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

    func setEqualizer(_ gains: [Double]?, toneGains: [Double]? = nil) {
        guard gains != currentEqualizerGains || toneGains != currentToneGains, let equalizer else { return }
        currentEqualizerGains = gains
        currentToneGains = toneGains
        if gains != nil, let toneGains, toneGains.count == 3 {
            toneGains.withUnsafeBufferPointer { MacMixEQSetToneGains(equalizer, $0.baseAddress, true) }
        } else if let gains, gains.count == 10 {
            gains.withUnsafeBufferPointer { MacMixEQSetGains(equalizer, $0.baseAddress, true) }
        } else {
            MacMixEQSetGains(equalizer, nil, false)
        }
    }

    func setMetering(_ enabled: Bool) {
        if let equalizer { MacMixEQSetMetering(equalizer, enabled) }
    }

    func spectrum() -> [Float]? {
        guard let equalizer else { return nil }
        var values = [Float](repeating: 0, count: Int(MacMixEQSpectrumBarCount))
        let available = values.withUnsafeMutableBufferPointer {
            MacMixEQCopySpectrum(equalizer, $0.baseAddress, $0.count)
        }
        return available ? values : nil
    }

    func hasRendered(_ gain: Float) -> Bool {
        if let equalizer, !MacMixEQIsSettled(equalizer) { return false }
        return abs(
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

    nonisolated var renderedFrames: UInt64 {
        audioIOContext.map { MacMixAudioIOContextRenderedFrames($0) } ?? 0
    }

    nonisolated var primaryRoutedDeviceUID: String? { routedPhysicalUIDs.first }
    nonisolated var physicalOutputUIDs: [String] { usesOutputRouting ? routedPhysicalUIDs : [outputDeviceUID] }

    /// nil when HAL cannot answer; a failed read never counts as a missing device.
    nonisolated var hasActiveOutputSubdevices: Bool? {
        guard aggregateID != kAudioObjectUnknown,
              let ids = readHALAudioObjectIDs(objectID: aggregateID,
                  selector: kAudioAggregateDevicePropertyActiveSubDeviceList) else { return nil }
        var uids = Set<String>()
        for id in ids {
            guard let uid = OutputRouteHealth.deviceUID(id) else { return nil }
            uids.insert(uid)
        }
        return Set(physicalOutputUIDs).isSubset(of: uids)
    }
    nonisolated var aggregateDeviceIDs: [AudioObjectID] { aggregateID == kAudioObjectUnknown ? [] : [aggregateID] }
    nonisolated var keepsRoutingPath: Bool { usesOutputRouting }

    nonisolated var renderedOutputGain: Float {
        audioIOContext.map { MacMixAudioIOContextRenderedOutputGain($0) } ?? 0
    }

    nonisolated func setOutputGain(_ gain: Float) {
        if let audioIOContext { MacMixAudioIOContextSetOutputGain(audioIOContext, gain) }
    }

    nonisolated func scheduleOutputGain(from: Float, to: Float, start: UInt64) {
        if let audioIOContext {
            MacMixAudioIOContextScheduleOutputGain(audioIOContext, from, to, start, 0.04)
        }
    }

    nonisolated var canOverlapRoutingReplacement: Bool {
        guard isRunning, renderedFrames > 0 else { return false }
        if usesOutputRouting {
            guard let layout = RoutedAudioLayout(aggregateID: aggregateID,
                deviceUIDs: routedPhysicalUIDs, tapCount: tapIDs.count) else { return false }
            return layout.signature == routingLayoutSignature
        }
        return gainStates.allSatisfy { id, state in
            guard let binding = tapBindings[id], let format = Self.tapFormat(for: binding.tapID) else { return false }
            return format.mSampleRate == state.format.mSampleRate
                && format.mChannelsPerFrame == state.format.mChannelsPerFrame
                && format.mFormatFlags == state.format.mFormatFlags
                && format.mBytesPerFrame == state.format.mBytesPerFrame
        }
    }

    nonisolated func updateGraphIfPossible(_ targets: [AppMixTarget], validatesFormat: Bool) -> Bool {
        let frames = renderedFrames
        let idle = frames == lastHealthFrames
        if idle != callbackWasIdle {
            DiagnosticLog.shared.record("mixer", idle ? "callback_progress_stopped" : "callback_progress_resumed",
                fields: ["aggregate": String(aggregateID), "action": "diagnostic_only"])
            callbackWasIdle = idle
        }
        lastHealthFrames = frames
        if (abnormalStopMonitor?.revision.load(ordering: .relaxed) ?? 0) != 0 {
            DiagnosticLog.shared.record("mixer", "aggregate_io_stopped_abnormally", level: "error",
                fields: ["aggregate": String(aggregateID)])
            return false
        }
        guard OutputRouteHealth.uintProperty(aggregateID, kAudioDevicePropertyDeviceIsAlive) == 1 else { return false }
        guard targets.allSatisfy({ target in
            target.airPlayRoutes == airPlayRoutes
                && target.outputDeviceUIDs.map {
                    AirPlayOutputRoute.validatedUIDs($0, routes: target.airPlayRoutes) == $0
                } != false
        }) else { return false }
        let nextRoutes = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.outputDeviceUIDs ?? [outputDeviceUID]) })
        let nextUsesRouting = targets.contains { $0.outputDeviceUIDs != nil }
        if usesOutputRouting {
            // Follow-system and access loss restore the native capture scope,
            // even when volume/EQ/metering still require a processing graph.
            guard nextUsesRouting,
                  Set(nextRoutes.values.flatMap { $0 }).isSubset(of: Set(routedPhysicalUIDs)),
                  nextRoutes.keys.allSatisfy({ routingTapIndices[$0] != nil }) else { return false }
        } else if nextUsesRouting {
            // A device-scoped tap cannot redirect audio sent to another device.
            // Recheck actual process destinations on every route validation.
            guard nextRoutes == outputRoutes else { return false }
            guard targets.allSatisfy({ target in
                guard target.airPlayRoutes.isEmpty else { return false }
                guard let selected = target.outputDeviceUIDs else { return true }
                return RoutedAudioLayout.canKeepNativeOutput(processIDs: target.audioObjectIDs,
                    selectedUIDs: selected, systemUID: outputDeviceUID)
            }) else { return false }
        }
        let nextGraph = Self.graph(for: targets)
        // Pure EQ edits on an unchanged graph only swap DSP parameters. Route,
        // sample-rate, process and normal reconciliation commands still validate HAL.
        if !validatesFormat && nextGraph == graph && nextRoutes == outputRoutes { return true }
        if usesOutputRouting {
            guard let layout = RoutedAudioLayout(aggregateID: aggregateID, deviceUIDs: routedPhysicalUIDs, tapCount: tapIDs.count),
                  layout.signature == routingLayoutSignature else { return false }
        }
        if validatesFormat {
            for (id, state) in gainStates {
                guard let binding = tapBindings[id], let format = Self.tapFormat(for: binding.tapID),
                      format.mSampleRate == state.format.mSampleRate,
                      format.mFormatID == state.format.mFormatID,
                      format.mFormatFlags == state.format.mFormatFlags,
                      format.mChannelsPerFrame == state.format.mChannelsPerFrame,
                      format.mBytesPerFrame == state.format.mBytesPerFrame,
                      format.mBitsPerChannel == state.format.mBitsPerChannel else { return false }
            }
        }
        for target in targets where target.equalizerGains != nil {
            if usesOutputRouting {
                guard gainStates[target.id]?.supportsEqualizer == true else { return false }
                continue
            }
            guard let state = gainStates[target.id], state.supportsEqualizer,
                  let binding = tapBindings[target.id], let format = Self.tapFormat(for: binding.tapID),
                  format.mSampleRate == state.format.mSampleRate,
                  format.mChannelsPerFrame == state.format.mChannelsPerFrame,
                  format.mFormatFlags == state.format.mFormatFlags,
                  format.mBitsPerChannel == state.format.mBitsPerChannel else { return false }
        }
        if usesOutputRouting, nextRoutes != outputRoutes, let audioIOContext {
            for (targetID, index) in routingTapIndices {
                let mask = destinationMask(for: nextRoutes[targetID] ?? [])
                MacMixAudioIOContextSetDestinationMask(audioIOContext, index, mask, false)
            }
            outputRoutes = nextRoutes
        }
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
                DiagnosticLog.shared.record("mixer", "tap_process_update_deferred", level: "error")
                Self.diagnosticsLogger.error(
                    "Deferring tap process update tap=\(binding.tapID) currentCount=\(binding.audioObjectIDs.count) requestedCount=\(nextAudioObjectIDs.count)"
                )
                continue
            }

            updatedGraph[targetID] = nextAudioObjectIDs
        }

        for targetID in graph.keys where nextGraph[targetID] == nil {
            gainStates[targetID]?.setTarget(1)
            gainStates[targetID]?.setEqualizer(nil)
            gainStates[targetID]?.setMetering(false)
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

    nonisolated func setEqualizer(_ gains: [Double]?, toneGains: [Double]?, for targetID: String) {
        gainStates[targetID]?.setEqualizer(gains, toneGains: toneGains)
    }

    nonisolated func setMetering(_ enabled: Bool, for targetID: String) {
        gainStates[targetID]?.setMetering(enabled)
    }

    nonisolated func spectrum(for targetID: String) -> [Float]? {
        gainStates[targetID]?.spectrum()
    }

    nonisolated func setAllGains(_ gain: Float) {
        for gainState in gainStates.values {
            gainState.setTarget(gain)
            gainState.setEqualizer(nil)
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
    private var outputRoutes: [String: [String]]
    private let airPlayRoutes: [String: AirPlayOutputRoute]

    nonisolated func silenceChangedAirPlayReceivers() {
        guard usesOutputRouting, let audioIOContext else { return }
        for (targetID, uids) in outputRoutes {
            let connected = AirPlayOutputRoute.validatedUIDs(uids, routes: airPlayRoutes)
            if connected != uids, let index = routingTapIndices[targetID] {
                // The callback owns destinationGains after AudioDeviceStart.
                // Publish only the atomic mask and let it perform the fade.
                MacMixAudioIOContextSetDestinationMask(audioIOContext, index, destinationMask(for: connected), false)
                // Keep the rendered route in sync with its mask. Otherwise a
                // later successful read could leave a restored receiver muted
                // because graph reconciliation thinks its route never changed.
                outputRoutes[targetID] = connected
            }
        }
    }
    private var routingTapIndices: [String: Int] = [:]
    private let usesOutputRouting: Bool
    private var routedPhysicalUIDs: [String] = []
    private var routingLayoutSignature: [UInt64] = []
    private var gainStates: [String: GainState] = [:]
    private var tapBindings: [String: TapBinding] = [:]
    private var tapIDs: [AudioObjectID] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var audioIOContext: MacMixAudioIOContextRef?
    private var isRunning = false
    private var lastHealthFrames: UInt64 = 0
    private var callbackWasIdle = false
    private var abnormalStopMonitor: OutputRouteHealthMonitor?

    private func destinationMask(for uids: [String]) -> UInt64 {
        let selected = Set(uids)
        return routedPhysicalUIDs.enumerated().reduce(UInt64(0)) { mask, item in
            guard item.offset < 64, selected.contains(item.element) else { return mask }
            return mask | (UInt64(1) << item.offset)
        }
    }

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
        var format: AudioStreamBasicDescription
        var inputBufferOffset: Int
        var inputBufferCount: Int
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
        outputDeviceUID: String,
        initialOutputGain: Float = 1,
        preferredClockUID: String? = nil
    ) {
        guard !Self.isInitializationCleanupPending else { return nil }
        let targets = targets.filter { !$0.audioObjectIDs.isEmpty }
        guard !targets.isEmpty else {
            return nil
        }

        self.graph = Self.graph(for: targets)
        self.tappedObjects = targets.flatMap(\.audioObjectIDs)
        self.outputDeviceUID = outputDeviceUID
        self.usesOutputRouting = targets.contains { $0.outputDeviceUIDs != nil }
        self.outputRoutes = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.outputDeviceUIDs ?? [outputDeviceUID]) })
        self.airPlayRoutes = targets.reduce(into: [:]) { routes, target in
            routes.merge(target.airPlayRoutes) { existing, _ in existing }
        }
        let clockUID = preferredClockUID ?? outputDeviceUID
        let physicalUIDs = Set(outputRoutes.values.flatMap { $0 }).sorted { left, right in
            if left == right { return false }
            if left == clockUID { return true }
            if right == clockUID { return false }
            return left < right
        }
        var tapRuntimes: [TapRuntime] = []
        var nextInputBufferOffset = 0
        for target in targets {
            var tapID = AudioObjectID(kAudioObjectUnknown)
            guard let configuration = Self.createProcessTap(
                audioObjectIDs: target.audioObjectIDs,
                outputDeviceUID: outputDeviceUID,
                usesOutputRouting: usesOutputRouting,
                tapID: &tapID
            ), let format = Self.tapFormat(for: tapID) else {
                if tapID != kAudioObjectUnknown {
                    tapIDs.append(tapID)
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
                    initialGain: startsAtTargetGain || usesOutputRouting ? gain : 1,
                    targetGain: gain
                )
            )
            nextInputBufferOffset += inputBufferCount
        }

        var aggregateDescription: [String: Any] = [
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
        if usesOutputRouting {
            aggregateDescription[kAudioAggregateDeviceSubDeviceListKey] = RoutedAudioLayout.subdevices(physicalUIDs)
            aggregateDescription[kAudioAggregateDeviceMainSubDeviceKey] = physicalUIDs.first
            // Non-stacked exposes separate streams. Stacked mirrors one stream
            // globally and cannot express different destinations for each app.
            aggregateDescription[kAudioAggregateDeviceIsStackedKey] = false
        }

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

        var outputBufferIndices = Array(
            Set(tapRuntimes.flatMap { runtime in
                (0..<runtime.inputBufferCount).map { runtime.outputBufferOffset + $0 }
            })
        ).sorted()
        var routingLayout: RoutedAudioLayout?
        if usesOutputRouting {
            var preparedLayout: RoutedAudioLayout?
            for attempt in 0..<6 {
                preparedLayout = RoutedAudioLayout(aggregateID: aggregateID, deviceUIDs: physicalUIDs, tapCount: tapRuntimes.count)
                if preparedLayout != nil { break }
                if attempt < 5 { Thread.sleep(forTimeInterval: 0.05) }
            }
            guard let layout = preparedLayout else {
                DiagnosticLog.shared.record("mixer", "routing_layout_unavailable", level: "error")
                Self.diagnosticsLogger.error("Output routing: unsupported or incomplete aggregate stream layout")
                stopAfterInitializationFailure()
                return nil
            }
            routingLayout = layout
            routedPhysicalUIDs = physicalUIDs
            routingLayoutSignature = layout.signature
            for index in tapRuntimes.indices {
                tapRuntimes[index].format = layout.inputs[index].format
                tapRuntimes[index].inputBufferOffset = layout.inputs[index].bufferOffset
                tapRuntimes[index].inputBufferCount = layout.inputs[index].bufferCount
            }
            // The existing context initializer needs a nonempty clearing list;
            // out-of-range indices are ignored for a tap-only (silent) aggregate.
            outputBufferIndices = layout.outputBufferIndices.isEmpty ? [0] : layout.outputBufferIndices.map(Int.init)
        }
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
        MacMixAudioIOContextSetInitialOutputGain(audioIOContext, initialOutputGain)

        if let routingLayout {
            for (index, runtime) in tapRuntimes.enumerated() {
                let channels = routedPhysicalUIDs.enumerated().flatMap { destinationIndex, uid in
                    (routingLayout.channelsByDevice[uid] ?? []).map { route in
                        MacMixAudioOutputChannel(format: route.format, bufferIndex: route.bufferIndex,
                            channelIndex: route.channelIndex, sourceChannel: route.sourceChannel,
                            destinationIndex: UInt32(destinationIndex))
                    }
                }
                guard channels.withUnsafeBufferPointer({ MacMixAudioIOContextSetOutputChannels(audioIOContext, index, $0.baseAddress, $0.count) }) else {
                    stopAfterInitializationFailure()
                    return nil
                }
                routingTapIndices[runtime.targetID] = index
                MacMixAudioIOContextSetDestinationMask(audioIOContext, index,
                    destinationMask(for: outputRoutes[runtime.targetID] ?? []), true)
            }
        }

        gainStates = Dictionary(uniqueKeysWithValues: tapRuntimes.enumerated().map { index, runtime in
            (
                runtime.targetID,
                GainState(context: audioIOContext, configurationIndex: index, format: runtime.format)
            )
        })

        for target in targets {
            if target.equalizerGains != nil, gainStates[target.id]?.supportsEqualizer != true {
                stopAfterInitializationFailure()
                return nil
            }
            gainStates[target.id]?.setEqualizer(target.equalizerGains, toneGains: target.equalizerToneGains)
        }

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

        if let routingLayout,
           MacMixAudioDisablePhysicalInputs(aggregateID, ioProc, UInt32(routingLayout.physicalInputStreamCount),
                                           UInt32(routingLayout.inputStreamCount)) != noErr {
            stopAfterInitializationFailure()
            return nil
        }

        guard targets.allSatisfy({ target in
            target.outputDeviceUIDs.map {
                AirPlayOutputRoute.validatedUIDs($0, routes: target.airPlayRoutes) == $0
            } != false
        }) else {
            stopAfterInitializationFailure()
            return nil
        }
        abnormalStopMonitor = OutputRouteHealthMonitor(objects: [aggregateID],
            selectors: [kAudioDevicePropertyIOStoppedAbnormally])
        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stopAfterInitializationFailure()
            return nil
        }

        isRunning = true
        DiagnosticCounters.shared.increment("graph_starts")
        DiagnosticLog.shared.record("mixer", "graph_started", fields: [
            "aggregate": String(aggregateID), "appCount": String(targets.count), "routed": String(usesOutputRouting)])
    }

    @discardableResult
    nonisolated func stop() -> AudioObjectID? {
        abnormalStopMonitor = nil
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
        DiagnosticLog.shared.record("mixer", "graph_initialization_failed", level: "error", fields: [
            "aggregate": String(aggregateID)])
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
        if !isStopped {
            // Keep ownership until HAL has actually stopped using the IO context.
            // The existing retirement worker retries teardown, never initialization.
            Self.pendingInitializationCleanup.wrappingIncrement(ordering: .relaxed)
            AppGainEngineRetirement(engine: self, completion: {
                Self.pendingInitializationCleanup.wrappingDecrement(ordering: .relaxed)
            }).start(on: Self.failedInitializationCleanupQueue)
        }
    }

    private static let pendingInitializationCleanup = ManagedAtomic<Int>(0)
    static var isInitializationCleanupPending: Bool {
        pendingInitializationCleanup.load(ordering: .relaxed) != 0
    }
    private static let failedInitializationCleanupQueue = DispatchQueue(
        label: "MacMix.FailedGraphCleanup", attributes: .concurrent)

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
            DiagnosticLog.shared.record("mixer", "tap_description_not_settable", level: "error", fields: ["osStatus": String(settableStatus)])
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
            DiagnosticLog.shared.record("mixer", "tap_listener_add_failed", level: "error", fields: ["osStatus": String(listenerStatus)])
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
                DiagnosticLog.shared.record("mixer", "tap_listener_remove_failed", level: "error", fields: ["osStatus": String(removalStatus)])
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
            DiagnosticLog.shared.record("mixer", "tap_process_write_failed", level: "error", fields: ["osStatus": String(status)])
            diagnosticsLogger.error(
                "Failed to set tap processes tap=\(binding.tapID) status=\(status)"
            )
            return false
        }

        let timeout = DispatchTime.now() + tapDescriptionUpdateTimeout
        let notificationResult = notification.wait(timeout: timeout)
        guard let appliedDescription = tapDescription(for: binding.tapID) else {
            binding.description.processes = previousAudioObjectIDs
            DiagnosticLog.shared.record("mixer", "tap_description_readback_failed", level: "error")
            diagnosticsLogger.error(
                "Failed to read back tap description tap=\(binding.tapID)"
            )
            return false
        }
        guard appliedDescription.processes == audioObjectIDs else {
            binding.description.processes = previousAudioObjectIDs
            DiagnosticLog.shared.record("mixer", "tap_process_confirmation_failed", level: "error")
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
        usesOutputRouting: Bool,
        tapID: inout AudioObjectID
    ) -> ProcessTapConfiguration? {
        // A stream tap preserves a multichannel device's PCM layout. Falling back to a stereo
        // tap on that device would make the aggregate input/output buffer layouts incompatible.
        let stereoMixdownTap = Self.configure(
            CATapDescription(stereoMixdownOfProcesses: audioObjectIDs),
            name: "MacMix Stereo Mixdown"
        )
        let candidates: [ProcessTapConfiguration]
        switch usesOutputRouting ? .noStreams : outputStreamSelection(outputDeviceUID: outputDeviceUID) {
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

            let createStatus = AudioHardwareCreateProcessTap(configuration.description, &tapID)
            if createStatus == noErr, tapID != kAudioObjectUnknown {
                return configuration
            }
            DiagnosticLog.shared.record("mixer", "tap_create_failed", level: "error", fields: ["osStatus": String(createStatus)])
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
        DiagnosticLog.shared.record("mixer", "graph_layout", fields: [
            "outputDevice": DiagnosticLog.shared.anonymous(outputDeviceUID), "aggregate": String(aggregateID),
            "taps": taps, "inputs": inputStreams, "outputs": outputStreams])
        let description = "Graph output=\(DiagnosticLog.shared.anonymous(outputDeviceUID)); \(taps); "
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

