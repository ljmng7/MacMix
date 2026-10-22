#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-output-recovery.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$ROOT" "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
health = (root / 'MacMix/Audio/OutputRouteHealth.swift').read_text()
budget = health[health.index('nonisolated struct OutputRecoveryBudget'):health.index('nonisolated struct OutputRouteHealth:')]
mixer = (root / 'MacMix/Audio/AppAudioMixer.swift').read_text()
recovery = mixer[mixer.index('    private func reconcileWithOutputHealth'):mixer.index('    private func protectRoutingProcesses')].replace('private func', 'func').replace('AppMixerCommand', 'Command').replace('AppMixTarget', 'Target')
projection = health[health.index('    func selecting'):health.index('    static func uintProperty')]
state = mixer[mixer.index('    private final class MemberOutputRecovery'):mixer.index('    private var engine:')].replace('private ', '')
guards = mixer[mixer.index('    private func releaseOutputSwitchMuteGuard'):mixer.index('    private func clampedGain')].replace('private func', 'func')
stop = mixer[mixer.index('    nonisolated func stop() -> AudioObjectID? {', mixer.index('private final class SharedProcessTapGainEngine')):mixer.index('    deinit {', mixer.index('private final class SharedProcessTapGainEngine'))]
stubs = r'''
typealias AudioObjectID = UInt32
let kAudioObjectUnknown: UInt32 = 0
struct Counter { var value: UInt64 = 0; func load(ordering: Ordering) -> UInt64 { value } }
enum Ordering { case relaxed, releasing }
final class Flag { func store(_ value: Bool, ordering: Ordering) {} }
struct Target {
    var requiresProcessing = true; var id = "player"; var outputDeviceUIDs: [String]?
    var audioObjectIDs: [UInt32] = [99]; var volume = 0.5
    var airPlayRoutes: [String:Int] = [:]
    var equalizerGains: [Double]?; var equalizerToneGains: [Double]?
    var isSoundNeutralWarm = false
}
struct Command { let revision: UInt64; let outputDeviceUID: String?; let targets: [Target]; var equalizerParametersOnly = false }
enum AppMixerResult { case applied, failed, superseded, deferred }
struct OutputRouteHealth: Equatable {
    let signature: String; let ready: Bool; let objects: [UInt32]
    var deviceSignatures: [String:String] = [:]
    var deviceIDs: [UInt32] = []
    var readyDeviceUIDs: Set<String> = []
    var objectsByDeviceUID: [String: [UInt32]] = [:]
    static var devices: [String:Self] = [:]
    static var onRead: (() -> Void)?
    static func read(uids: [String]) -> Self {
        onRead?()
        let readings = Set(uids).sorted().map { ($0, devices[$0] ?? Self(signature: "missing", ready: false, objects: [])) }
        return Self(signature: readings.map { $0.0 + $0.1.signature }.joined(separator: ":"),
            ready: readings.allSatisfy { $0.1.ready }, objects: readings.flatMap { $0.1.objects },
            deviceSignatures: Dictionary(uniqueKeysWithValues: readings.map { ($0.0, $0.1.signature) }),
            readyDeviceUIDs: Set(readings.filter { $0.1.ready }.map { $0.0 }),
            objectsByDeviceUID: Dictionary(uniqueKeysWithValues: readings.map { ($0.0, $0.1.objects) }))
    }
}
__PROJECTION__
final class OutputRouteHealthMonitor { var revision = Counter(); init(objects: [UInt32]) {} }
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    func anonymous(_ id: String) -> String { id }
    func record(_ category: String, _ event: String, level: String = "info", fields: [String:String]) {}
}
enum RoutedAudioLayout {
    static func canKeepNativeOutput(processIDs: [UInt32], selectedUIDs: [String], systemUID: String) -> Bool { selectedUIDs == [systemUID] }
}
enum AirPlayOutputRoute {
    static func validatedUIDs(_ uids: [String], routes: [String:Int]) -> [String] { uids }
}
protocol AppGainEngine { var keepsRoutingPath: Bool { get }; var outputDeviceUID: String { get }; var tappedObjects: [UInt32] { get } }
final class SharedProcessTapGainEngine: AppGainEngine {
    static var isInitializationCleanupPending = false
    static var failingIDs = Set<String>()
    static var attempts: [String:Int] = [:]
    static var nextAggregate: UInt32 = 1000
    static var onInit: (() -> Void)?
    let id: String; let target: Target; let outputDeviceUID: String
    var gain: Float = 0; var equalizer: [Double]?
    var renderedFrames: UInt64 = 0
    let aggregateDeviceIDs: [UInt32]
    var physicalOutputUIDs: [String] { target.outputDeviceUIDs ?? [outputDeviceUID] }
    var hasActiveOutputSubdevices: Bool? = nil
    var canOverlapRoutingReplacement: Bool { target.outputDeviceUIDs?.isEmpty == false }
    var tappedObjects: [UInt32] { target.audioObjectIDs }
    var keepsRoutingPath: Bool { target.outputDeviceUIDs != nil }
    init?(targets: [Target], startsAtTargetGain: Bool, outputDeviceUID: String) {
        let t = targets[0]; Self.attempts[t.id, default: 0] += 1; Self.onInit?()
        guard !Self.failingIDs.contains(t.id) else { return nil }
        id = t.id; target = t; self.outputDeviceUID = outputDeviceUID
        Self.nextAggregate += 1; aggregateDeviceIDs = [Self.nextAggregate]
    }
    func silenceChangedAirPlayReceivers() {}
    func updateGraphIfPossible(_ targets: [Target], validatesFormat: Bool) -> Bool {
        !Self.failingIDs.contains(id) && targets[0].outputDeviceUIDs == target.outputDeviceUIDs
    }
}
final class AppGainEngineGroup: AppGainEngine {
    let outputDeviceUID: String
    var members: [String:SharedProcessTapGainEngine] = [:]
    init(outputDeviceUID: String) { self.outputDeviceUID = outputDeviceUID }
    var tappedObjects: [UInt32] { members.values.flatMap(\.tappedObjects) }
    var keepsRoutingPath: Bool { members.values.contains { $0.keepsRoutingPath } }
    func setGain(_ gain: Float, for id: String) { members[id]?.gain = gain }
    func setEqualizer(_ gains: [Double]?, toneGains: [Double]?, for id: String) { members[id]?.equalizer = gains }
}
struct Retirement { var isComplete = true }
final class RecoveryHarness {
    static let isSupported = true
    var engine: (any AppGainEngine)?
    var pendingRetirements: [Retirement] = []
    var cachedSpectra: [String:Int] = [:]
    var meterSubscriptions: [String: [Int]] = [:]
    var routingGraphActive = Flag()
    var currentRevision: UInt64 = 0
    var switchMuted = false; var routingMuted = false
    var retirements: [String] = []
    var group: AppGainEngineGroup? { engine as? AppGainEngineGroup }
    func isCurrent(_ command: Command) -> Bool { currentRevision == command.revision }
    func enqueueRetirement(_ old: any AppGainEngine) {
        if let member = old as? SharedProcessTapGainEngine { retirements.append(member.id) }
        else if let group = old as? AppGainEngineGroup { retirements += group.members.keys.sorted() }
    }
    func waitForPendingAggregateRemoval(command: Command) -> Bool { true }
    func prepareForUnityHandoff(_ old: any AppGainEngine) {}
    func applyMeterSubscriptions() {}
    func protectRoutingProcesses(_ objects: [UInt32]) -> Bool { routingMuted = true; return true }
    func rebuildMember(_ target: Target, current: SharedProcessTapGainEngine, group: AppGainEngineGroup, command: Command) -> Bool {
        group.members.removeValue(forKey: target.id); enqueueRetirement(current)
        guard let next = SharedProcessTapGainEngine(targets: [target], startsAtTargetGain: true, outputDeviceUID: group.outputDeviceUID) else { return false }
        group.members[target.id] = next; return true
    }
    func replacementRoutingGraphWhilePlaying(_ current: SharedProcessTapGainEngine, targets: [Target], command: Command) -> SharedProcessTapGainEngine? {
        guard let next = SharedProcessTapGainEngine(targets: targets, startsAtTargetGain: true, outputDeviceUID: current.outputDeviceUID) else { return nil }
        enqueueRetirement(current); return next
    }
    func clampedGain(_ volume: Double) -> Float { Float(volume) }
    func releaseOutputSwitchMuteGuard() { switchMuted = false }
    @discardableResult func releaseRoutingMuteGuard() -> Bool { routingMuted = false; return true }
    func probeSystemAudioPermission() -> Bool { true }
    var outputting = Set<String>()
    var renders = true
    func readOutputtingTargets(_ targets: [Target]) -> Set<String> { outputting.intersection(targets.map(\.id)) }
    func waitForRender(_ member: SharedProcessTapGainEngine, command: Command) -> Bool { renders }
'''
cleanup = r'''
var halCalls: [String] = []
var stopStatus: Int32 = 0
func AudioDeviceStop(_ id: UInt32, _ io: Int) -> Int32 { halCalls.append("stop"); return stopStatus }
func AudioDeviceDestroyIOProcID(_ id: UInt32, _ io: Int) -> Int32 { halCalls.append("io"); return 0 }
func MacMixAudioIOContextDestroy(_ context: Int) { halCalls.append("context") }
func AudioHardwareDestroyAggregateDevice(_ id: UInt32) -> Int32 { halCalls.append("aggregate"); return 0 }
func AudioHardwareDestroyProcessTap(_ id: UInt32) -> Int32 { halCalls.append("tap"); return 0 }
final class StopHarness {
    var aggregateID: UInt32 = 10; var tapIDs: [UInt32] = [20]
    var abnormalStopMonitor: Int?
    var ioProc: Int? = 1; var audioIOContext: Int? = 1; var isRunning = true
    static func audioObjectExists(_ id: UInt32) -> Bool { true }
    static func didStop(_ status: Int32) -> Bool { status == 0 }
    static func didDestroy(_ status: Int32) -> Bool { status == 0 }
'''
guard_stubs = r'''
final class ProcessTapMuteGuard {
    var isStopped = false; var allowsStop = true
    init() {}
    init?(audioObjectIDs: [UInt32]) { if audioObjectIDs.isEmpty { return nil } }
    func stop() { if allowsStop { isStopped = true } }
}
final class GuardHarness {
    var outputSwitchMuteGuard: ProcessTapMuteGuard?
    var routingMuteGuard: ProcessTapMuteGuard?
    var routingGuardObjects: [UInt32] = []
'''
stubs = stubs.replace('\n}\n__PROJECTION__', '\n' + projection + '\n}')
(out / 'Tests.swift').write_text((root / 'tests/OutputRouteRecoveryTests.swift').read_text() + '\n' + budget + stubs + state + recovery + '\n}\n' + cleanup + stop + '\n}\n' + guard_stubs + guards + '\n}\n')
PY
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/ModuleCache" "$TEST_DIR/Tests.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
