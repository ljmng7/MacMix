import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

// Clock-controlled tests exercise the production budget, not real sleeping.
func testBudget() {
    var initial = OutputRecoveryBudget()
    initial.observe("healthy-startup", now: 10, waitForStability: false)
    check(initial.canAttempt(ready: true, now: 10), "healthy startup has no recovery stability delay")
    initial.failed(now: 10)
    check(!initial.canAttempt(ready: true, now: 10.2), "startup failures still back off")
    var budget = OutputRecoveryBudget()
    budget.observe("uid:object1:format1", now: 0)
    check(!budget.canAttempt(ready: true, now: 0.2), "wait for stream stability")
    check(!budget.canAttempt(ready: false, now: 2), "never rebuild unavailable output")
    check(budget.canAttempt(ready: true, now: 0.4), "ready output can recover")
    budget.failed(now: 0.4)
    check(!budget.canAttempt(ready: true, now: 1), "failure backoff")
    budget.observe("uid:object1:format1", now: 1)
    check(budget.failures == 1, "unchanged polls must not reset retry budget")
    for i in 1...3 { budget.failed(now: Double(i * 10)) }
    check(!budget.canAttempt(ready: true, now: 100), "bounded retry exhaustion")
    budget.observe("uid:object2:format1", now: 100)
    check(budget.failures == 0 && budget.canAttempt(ready: true, now: 101), "same UID new instance recovers")
}

func settle(_ harness: RecoveryHarness, _ command: Command) -> AppMixerResult {
    _ = harness.reconcileWithOutputHealth(command)
    Thread.sleep(forTimeInterval: 0.32)
    return harness.reconcileWithOutputHealth(command)
}

func testRecovery() {
    SharedProcessTapGainEngine.failingIDs = []
    SharedProcessTapGainEngine.attempts = [:]
    let h = RecoveryHarness()
    let command = Command(revision: 1, outputDeviceUID: "same-uid", targets: [Target()])
    h.currentRevision = 1
    OutputRouteHealth.devices = ["same-uid": .init(signature: "device1", ready: true, objects: [1, 10])]
    check(h.reconcileWithOutputHealth(command) == .applied, "healthy startup starts without delay")
    let original = h.group!.members["player"]!
    for _ in 0..<50 { check(h.reconcileWithOutputHealth(command) == .applied, "pause stays healthy") }
    check(h.group?.members["player"] === original && h.retirements.isEmpty, "pause never rebuilds")
    OutputRouteHealth.devices["same-uid"] = .init(signature: "dead", ready: false, objects: [1, 10])
    check(h.reconcileWithOutputHealth(command) == .deferred && h.engine == nil, "dead native output releases affected graph")
    OutputRouteHealth.devices["same-uid"] = .init(signature: "device2", ready: true, objects: [2, 20])
    check(settle(h, command) == .applied, "same UID new instance recovers")
    h.memberOutputRecovery["player"]?.monitor?.revision.value += 1
    check(h.reconcileWithOutputHealth(command) == .deferred && h.engine == nil, "transient notification invalidates affected graph")
    Thread.sleep(forTimeInterval: 0.32)
    check(h.reconcileWithOutputHealth(command) == .applied, "latched recovery")
    let current = h.group!.members["player"]!
    OutputRouteHealth.onRead = { h.currentRevision = 2 }
    check(h.reconcileWithOutputHealth(command) == .superseded, "old HAL read cancelled")
    check(h.group?.members["player"] === current, "old read leaves current graph intact")
    OutputRouteHealth.onRead = nil
    h.currentRevision = 1
    SharedProcessTapGainEngine.failingIDs = ["player"]
    check(h.reconcileWithOutputHealth(command) == .deferred && h.engine == nil, "member failure is retryable")
    let attempts = SharedProcessTapGainEngine.attempts["player"]
    check(h.reconcileWithOutputHealth(command) == .deferred && SharedProcessTapGainEngine.attempts["player"] == attempts,
          "failure backoff prevents a spin")
    SharedProcessTapGainEngine.failingIDs = []
    let pending = RecoveryHarness(); pending.currentRevision = 1
    SharedProcessTapGainEngine.isInitializationCleanupPending = true
    check(pending.reconcileWithOutputHealth(command) == .deferred && pending.engine == nil, "pending cleanup prevents overlapping initialization")
    SharedProcessTapGainEngine.isInitializationCleanupPending = false

    let rapid = RecoveryHarness(); rapid.currentRevision = 0
    OutputRouteHealth.devices["same-uid"] = .init(signature: "route0", ready: true, objects: [100])
    check(rapid.reconcileWithOutputHealth(Command(revision: 0, outputDeviceUID: "same-uid", targets: [Target()])) == .applied,
          "burst starts with a healthy graph")
    let initialAttempts = SharedProcessTapGainEngine.attempts["player"]
    for revision in 1...20 {
        rapid.currentRevision = UInt64(revision)
        OutputRouteHealth.devices["same-uid"] = .init(signature: "route\(revision)", ready: true, objects: [UInt32(revision)])
        let next = Command(revision: UInt64(revision), outputDeviceUID: "same-uid", targets: [Target()])
        check(rapid.reconcileWithOutputHealth(next) == .deferred, "burst waits for stability")
    }
    check(SharedProcessTapGainEngine.attempts["player"] == initialAttempts, "burst creates no intermediate graphs")
    Thread.sleep(forTimeInterval: 0.32)
    check(rapid.reconcileWithOutputHealth(Command(revision: 20, outputDeviceUID: "same-uid", targets: [Target()])) == .applied,
          "only final burst route starts")
}

func testIndependentOutputRecovery() {
    SharedProcessTapGainEngine.failingIDs = []
    SharedProcessTapGainEngine.attempts = [:]
    OutputRouteHealth.devices = [
        "speakers": .init(signature: "speaker1", ready: true, objects: [1]),
        "usb": .init(signature: "usb1", ready: true, objects: [2])]
    let h = RecoveryHarness(); h.currentRevision = 1
    let healthy = Target(id: "healthy", audioObjectIDs: [11], volume: 0, equalizerGains: [3])
    let routed = Target(id: "routed", outputDeviceUIDs: ["usb"], audioObjectIDs: [22])
    let command = Command(revision: 1, outputDeviceUID: "speakers", targets: [healthy, routed])
    check(h.reconcileWithOutputHealth(command) == .applied, "both applications start")
    let original = h.group!.members["healthy"]!
    OutputRouteHealth.devices["usb"] = .init(signature: "usb-dead", ready: false, objects: [2])
    check(h.reconcileWithOutputHealth(command) == .deferred, "USB failure defers only routed member")
    check(h.group?.members["healthy"] === original && original.gain == 0 && original.equalizer == [3],
          "healthy member keeps identity, mute and EQ")
    check(h.memberRouteMuteGuards["routed"] != nil && !h.retirements.contains("healthy"),
          "failed explicit route stays guarded without touching healthy graph")
    Thread.sleep(forTimeInterval: 0.32)
    check(h.reconcileWithOutputHealth(command) == .applied, "unavailable explicit route becomes a silent graph")
    check(h.group?.members["routed"]?.target.outputDeviceUIDs == [], "offline routing never falls back to speakers")
    check(h.group?.members["healthy"] === original, "silent graph creation preserves healthy app")
    OutputRouteHealth.devices["usb"] = .init(signature: "usb2", ready: true, objects: [3])
    check(settle(h, command) == .applied && h.group?.members["routed"]?.target.outputDeviceUIDs == ["usb"],
          "USB return rebuilds only affected app")
    check(h.group?.members["healthy"] === original, "reconnect preserves healthy graph")

    // Initialization failure and repeated retry failure remain isolated too.
    SharedProcessTapGainEngine.failingIDs = ["routed"]
    check(h.reconcileWithOutputHealth(command) == .deferred, "routed initialization failure defers")
    for _ in 0..<20 { _ = h.reconcileWithOutputHealth(command) }
    check(h.group?.members["healthy"] === original && h.memberRouteMuteGuards["routed"] != nil,
          "failed routed attempts retain healthy audio and native mute guard")
    var adjustedHealthy = healthy
    adjustedHealthy.volume = 0.25
    adjustedHealthy.equalizerGains = [6]
    h.currentRevision = 2
    let adjusted = Command(revision: 2, outputDeviceUID: "speakers", targets: [adjustedHealthy, routed])
    check(h.reconcileWithOutputHealth(adjusted) == .deferred && h.group?.members["healthy"] === original,
          "healthy controls still update during another member's backoff")
    check(original.gain == 0.25 && original.equalizer == [6], "healthy volume and EQ edits are applied")
    let native = Command(revision: 2, outputDeviceUID: "speakers", targets: [healthy])
    let routeGuard = h.memberRouteMuteGuards["routed"]!
    routeGuard.allowsStop = false
    check(h.reconcileWithOutputHealth(native) == .applied && h.memberRouteMuteGuards["routed"] === routeGuard,
          "failed guard stop retains ownership without interrupting healthy app")
    routeGuard.allowsStop = true
    check(h.reconcileWithOutputHealth(native) == .applied && h.memberRouteMuteGuards["routed"] == nil,
          "removing routing releases its guard after HAL allows stop")
    SharedProcessTapGainEngine.failingIDs = []

    // One routed app keeps its remaining healthy destination when another fails.
    let multi = Target(id: "multi", outputDeviceUIDs: ["usb", "speakers"], audioObjectIDs: [33])
    let mixed = Command(revision: 2, outputDeviceUID: "speakers", targets: [healthy, multi])
    check(h.reconcileWithOutputHealth(mixed) == .applied, "healthy multi-output starts")
    OutputRouteHealth.devices["usb"] = .init(signature: "usb-offline", ready: false, objects: [3])
    check(settle(h, mixed) == .applied && h.group?.members["multi"]?.target.outputDeviceUIDs == ["speakers"],
          "remaining selected destination keeps playing without native fallback")
    check(h.group?.members["healthy"] === original, "multi-output failure leaves sibling untouched")

    // A hardware notification on USB does not invalidate speaker-only members.
    OutputRouteHealth.devices["usb"] = .init(signature: "usb3", ready: true, objects: [4])
    _ = settle(h, mixed)
    h.memberOutputRecovery["multi"]?.monitor?.revision.value += 1
    _ = settle(h, mixed)
    check(h.group?.members["healthy"] === original, "latched USB event remains member scoped")
}

func testHALCleanup() {
    halCalls = []
    stopStatus = -99
    let h = StopHarness()
    _ = h.stop()
    check(h.audioIOContext != nil && h.ioProc != nil, "failed stop retains callback storage")
    check(!halCalls.contains("context") && !halCalls.contains("tap"), "no destruction while IO active")
    stopStatus = 0
    _ = h.stop()
    check(halCalls.suffix(5) == ["stop", "io", "context", "aggregate", "tap"], "teardown order")
    check(h.audioIOContext == nil && h.ioProc == nil && h.aggregateID == 0 && h.tapIDs == [0], "all resources released")
    halCalls = []
    _ = h.stop()
    check(halCalls.isEmpty, "cleanup idempotent")
}

func testMuteGuardCleanup() {
    let h = GuardHarness()
    h.outputSwitchMuteGuard = ProcessTapMuteGuard()
    h.routingMuteGuard = ProcessTapMuteGuard()
    h.routingGuardObjects = [99]
    h.releaseOutputSwitchMuteGuard()
    check(h.outputSwitchMuteGuard == nil, "output switch guard released")
    check(h.releaseRoutingMuteGuard() && h.routingGuardObjects.isEmpty, "routing guard released")
    h.routingMuteGuard = ProcessTapMuteGuard()
    h.routingMuteGuard?.allowsStop = false
    check(!h.releaseRoutingMuteGuard() && h.routingMuteGuard != nil, "failed teardown retains guard ownership")
    h.routingMuteGuard?.allowsStop = true
    check(h.releaseRoutingMuteGuard() && h.routingMuteGuard == nil, "guard teardown retried safely")
}

func testWarmGraphPolicy() {
    check(WarmGraphPolicy.admits(soundNeutral: false, metering: false, hasMember: false, outputting: false, lastOutputAt: nil, now: 0),
          "audible processing is always admitted")
    check(WarmGraphPolicy.admits(soundNeutral: true, metering: true, hasMember: false, outputting: false, lastOutputAt: nil, now: 0),
          "visible spectrum admits a neutral graph")
    check(WarmGraphPolicy.admits(soundNeutral: true, metering: false, hasMember: false, outputting: true, lastOutputAt: 0, now: 0),
          "playing neutral app keeps its warm graph")
    check(!WarmGraphPolicy.admits(soundNeutral: true, metering: false, hasMember: false, outputting: false, lastOutputAt: nil, now: 0),
          "idle neutral app is not tapped")
    check(WarmGraphPolicy.admits(soundNeutral: true, metering: false, hasMember: true, outputting: false, lastOutputAt: 0, now: 9),
          "short pause keeps the graph")
    check(!WarmGraphPolicy.admits(soundNeutral: true, metering: false, hasMember: true, outputting: false, lastOutputAt: 0, now: 10),
          "long pause releases the graph")
}

func testStallDetector() {
    var paused = OutputStallDetector()
    for now in stride(from: 0.0, through: 30, by: 2) {
        check(paused.observe(graph: 1, frames: 0, outputting: false, deviceReady: true, subdevicesActive: nil, now: now) == nil,
              "paused app with idle callback is never a stall")
    }
    check(paused.observe(graph: 1, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 31) == nil,
          "resume gets an output grace period")
    check(paused.observe(graph: 1, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 32.5) == nil,
          "grace period not yet elapsed")
    check(paused.observe(graph: 1, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 33.1) == "callback_stalled",
          "playing app with frozen callback is a stall")
    check(paused.observe(graph: 2, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 33.2) == nil,
          "a new graph starts with fresh tracking")

    var playing = OutputStallDetector()
    for (index, now) in stride(from: 0.0, through: 20, by: 2).enumerated() {
        check(playing.observe(graph: 1, frames: UInt64(index * 512), outputting: true, deviceReady: true, subdevicesActive: true, now: now) == nil,
              "rendering graph is healthy")
    }

    var unavailable = OutputStallDetector()
    for now in stride(from: 0.0, through: 20, by: 2) {
        check(unavailable.observe(graph: 1, frames: 0, outputting: true, deviceReady: false, subdevicesActive: nil, now: now) == nil,
              "headphones off: unavailable output waits instead of rebuilding")
    }
    check(unavailable.observe(graph: 1, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 21) == nil,
          "worn again: wait for output grace period")
    check(unavailable.observe(graph: 1, frames: 0, outputting: true, deviceReady: true, subdevicesActive: nil, now: 23) == "callback_stalled",
          "worn again without rendering recovers")

    var missing = OutputStallDetector()
    check(missing.observe(graph: 1, frames: 1, outputting: true, deviceReady: true, subdevicesActive: false, now: 0) == nil, "subdevice grace")
    check(missing.observe(graph: 1, frames: 2, outputting: true, deviceReady: true, subdevicesActive: nil, now: 1) == nil,
          "unreadable subdevices are never a failure")
    check(missing.observe(graph: 1, frames: 3, outputting: true, deviceReady: true, subdevicesActive: false, now: 2) == nil,
          "unknown read restarts subdevice timing")
    check(missing.observe(graph: 1, frames: 4, outputting: true, deviceReady: true, subdevicesActive: false, now: 4) == "subdevice_inactive",
          "inactive output subdevice is a stall even while frames advance")
}

func testStallLimiter() {
    var limiter = OutputStallLimiter()
    for now in [0.0, 1, 2] {
        check(limiter.canRebuild(now: now), "attempt allowed")
        limiter.began(now: now)
    }
    check(!limiter.canRebuild(now: 3), "rolling window caps rapid rebuilds")
    limiter.exhaust(now: 3)
    check(limiter.isHolding(now: 29.9) && !limiter.canRebuild(now: 29.9), "hold until oldest attempt expires")
    check(limiter.canRebuild(now: 30.1), "recovery is never abandoned permanently")

    var backoff = OutputStallLimiter()
    backoff.began(now: 10); backoff.failed(now: 10)
    check(backoff.isHolding(now: 10.9) && !backoff.isHolding(now: 11), "first silent rebuild backs off 1 second")
    backoff.began(now: 11); backoff.failed(now: 11)
    check(backoff.isHolding(now: 12.9) && !backoff.isHolding(now: 13), "second silent rebuild backs off 2 seconds")
    backoff.succeeded()
    check(!backoff.isHolding(now: 13), "success clears backoff")
}

func testSilentStallRecovery() {
    SharedProcessTapGainEngine.failingIDs = []
    SharedProcessTapGainEngine.attempts = [:]
    OutputRouteHealth.devices = [
        "speakers": .init(signature: "speaker1", ready: true, objects: [1]),
        "airpods": .init(signature: "airpods1", ready: true, objects: [2])]
    let follow = Target(id: "follow", audioObjectIDs: [11])
    let routed = Target(id: "routed", outputDeviceUIDs: ["airpods"], audioObjectIDs: [22])
    let command = Command(revision: 1, outputDeviceUID: "airpods", targets: [follow])
    let routedCommand = Command(revision: 1, outputDeviceUID: "speakers", targets: [routed])
    let recovers = RecoveryHarness(), failOpen = RecoveryHarness(), muted = RecoveryHarness(), paused = RecoveryHarness()
    let cases = [(recovers, command), (failOpen, command), (muted, routedCommand), (paused, command)]
    for (h, c) in cases {
        h.currentRevision = 1
        check(h.reconcileWithOutputHealth(c) == .applied, "stall test graph starts")
        if h !== paused { h.outputting = Set(c.targets.map(\.id)) }
    }
    let originals = cases.map { $0.0.group!.members[$0.1.targets[0].id]! }
    for (h, c) in cases { check(h.reconcileWithOutputHealth(c) == .applied, "output grace period starts") }
    Thread.sleep(forTimeInterval: 2.1)
    recovers.renders = true; failOpen.renders = false; muted.renders = false

    check(recovers.reconcileWithOutputHealth(command) == .applied, "stalled playing graph rebuilds")
    check(recovers.group?.members["follow"] !== originals[0] && recovers.retirements == ["follow"],
          "only the stalled graph is replaced")

    check(failOpen.reconcileWithOutputHealth(command) == .deferred && failOpen.group?.members["follow"] == nil,
          "silent rebuild is retired")
    check(failOpen.memberRouteMuteGuards.isEmpty, "following the system fails open to native output")
    let attempts = SharedProcessTapGainEngine.attempts["follow"]
    check(failOpen.reconcileWithOutputHealth(command) == .deferred && SharedProcessTapGainEngine.attempts["follow"] == attempts,
          "silent rebuild backs off instead of spinning")

    check(muted.reconcileWithOutputHealth(routedCommand) == .deferred && muted.group?.members["routed"] == nil,
          "silent explicit route is retired")
    check(muted.memberRouteMuteGuards["routed"] != nil, "explicit route stays muted while recovery waits")

    check(paused.reconcileWithOutputHealth(command) == .applied && paused.group?.members["follow"] === originals[3]
          && paused.retirements.isEmpty, "paused app with idle callback is untouched")
    // An explicit route whose destinations are all offline is silent by design.
    OutputRouteHealth.devices["airpods"] = .init(signature: "airpods-off", ready: false, objects: [2])
    let offline = RecoveryHarness(); offline.currentRevision = 1
    offline.outputting = ["routed"]
    _ = offline.reconcileWithOutputHealth(routedCommand)
    Thread.sleep(forTimeInterval: 0.32)
    check(offline.reconcileWithOutputHealth(routedCommand) == .applied && offline.group?.members["routed"]?.target.outputDeviceUIDs == [],
          "offline explicit route starts a silent graph")
    let silent = offline.group!.members["routed"]!
    Thread.sleep(forTimeInterval: 2.1)
    _ = offline.reconcileWithOutputHealth(routedCommand)
    check(offline.reconcileWithOutputHealth(routedCommand) == .applied && offline.group?.members["routed"] === silent,
          "intentionally silent offline route is never treated as a stall")
}

// Dragging an idle app's slider supersedes the command that creates its graph;
// a playing sibling must keep its graph instead of restarting on every edit.
func testSupersededCommandKeepsPlayingGraphs() {
    SharedProcessTapGainEngine.failingIDs = []
    SharedProcessTapGainEngine.attempts = [:]
    OutputRouteHealth.devices = ["speakers": .init(signature: "speaker1", ready: true, objects: [1])]
    let h = RecoveryHarness(); h.currentRevision = 1
    let music = Target(id: "music", audioObjectIDs: [11], volume: 1, equalizerGains: [3])
    check(h.reconcileWithOutputHealth(Command(revision: 1, outputDeviceUID: "speakers", targets: [music])) == .applied,
          "playing app starts")
    let playing = h.group!.members["music"]!
    SharedProcessTapGainEngine.onInit = { h.currentRevision += 1 }
    defer { SharedProcessTapGainEngine.onInit = nil }
    h.currentRevision = 2
    let first = Command(revision: 2, outputDeviceUID: "speakers", targets: [music, Target(id: "safari", audioObjectIDs: [22], volume: 0.95)])
    check(h.reconcileWithOutputHealth(first) == .superseded, "newer slider edit supersedes graph creation")
    check(h.group?.members["music"] === playing && !h.retirements.contains("music"), "superseded edit keeps playing graph")
    check(h.group?.members["safari"] != nil && !h.routingMuted && !h.switchMuted, "built graph survives and mute guards fail open")
    for revision in 3...40 {
        h.currentRevision = UInt64(revision)
        let volume = 0.95 - Double(revision) * 0.02
        let edit = Command(revision: UInt64(revision), outputDeviceUID: "speakers",
            targets: [music, Target(id: "safari", audioObjectIDs: [22], volume: volume)])
        check(h.reconcileWithOutputHealth(edit) == .applied, "later slider edits only update gain")
    }
    check(h.group?.members["music"] === playing && h.retirements.isEmpty, "slider drag never restarts the playing app")
    check(SharedProcessTapGainEngine.attempts["safari"] == 1 && SharedProcessTapGainEngine.attempts["music"] == 1,
          "slider drag creates each graph once")
    check(abs(Double(h.group!.members["safari"]!.gain) - 0.15) < 0.0001 && playing.gain == 1, "final gains applied")
}

@main struct Tests {
    static func main() {
        testBudget()
        testRecovery()
        testIndependentOutputRecovery()
        testSupersededCommandKeepsPlayingGraphs()
        testHALCleanup()
        testMuteGuardCleanup()
        testWarmGraphPolicy()
        testStallDetector()
        testStallLimiter()
        testSilentStallRecovery()
        print("Output route recovery: budget, same UID, transient event, pause, supersession, superseded slider drag, failure, independent apps, partial destinations, guarded offline routes, HAL cleanup, warm graph policy and silent stall recovery passed")
    }
}
