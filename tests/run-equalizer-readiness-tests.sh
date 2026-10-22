#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-eq-readiness.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$ROOT" "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
mixer = (root / 'MacMix/Audio/AppAudioMixer.swift').read_text()
model = (root / 'MacMix/Audio/AudioModel.swift').read_text()
health = (root / 'MacMix/Audio/OutputRouteHealth.swift').read_text()
target = mixer[mixer.index('nonisolated struct AppMixTarget:'):mixer.index('nonisolated struct AppMixerSnapshot:')]
start = health.index('nonisolated enum WarmGraphPolicy')
policy = health[start:health.index('\nnonisolated struct', start)]
start = model.index('        if equalizerStore.isFeatureActive {', model.index('    private func mixTarget('))
configuration = model[start:model.index('\n        }\n', start) + len('\n        }\n')]
source = '''
import Foundation
typealias AudioObjectID = UInt32
struct AirPlayOutputRoute: Sendable, Equatable {}
struct Configuration {
    var isEnabled = false
    var normalizedGains = Array(repeating: 0.0, count: 10)
    var normalizedToneGains: [Double]? = nil
}
struct Store {
    var isFeatureActive = true
    var configurations: [String: Configuration] = [:]
    func configuration(for id: String) -> Configuration { configurations[id] ?? Configuration() }
}
struct App { var bundleID = "player" }
func makeTarget(_ equalizerStore: Store, volume: Double = 1) -> AppMixTarget {
    let app = App()
    var target = AppMixTarget(id: app.bundleID, audioObjectIDs: [1], volume: volume)
''' + configuration + '''
    return target
}
// Mirrors the mixer admission: processing or metering, then the warm policy.
func admitted(_ t: AppMixTarget, metering: Bool = false, hasMember: Bool = false,
              outputting: Bool = false, lastOutputAt: TimeInterval? = nil, now: TimeInterval = 0) -> Bool {
    (t.requiresProcessing || metering) && WarmGraphPolicy.admits(soundNeutral: t.isSoundNeutralWarm,
        metering: metering, hasMember: hasMember, outputting: outputting, lastOutputAt: lastOutputAt, now: now)
}
var store = Store()
let untouched = makeTarget(store)
precondition(!untouched.keepsEqualizerWarm && !admitted(untouched, outputting: true), "Apps without EQ settings are never tapped")
precondition(admitted(untouched, metering: true), "Visible spectrum still admits an untouched app")
store.configurations["player"] = Configuration()
let flat = makeTarget(store)
precondition(flat.equalizerGains == nil && flat.isSoundNeutralWarm, "Saved Flat is warm and sound-neutral")
precondition(admitted(flat, outputting: true), "Playing Flat app keeps its graph")
precondition(admitted(flat, metering: true, hasMember: true, outputting: true) == admitted(flat, hasMember: true, outputting: true),
             "Showing/hiding spectrum keeps graph membership while playing")
precondition(admitted(flat, hasMember: true, lastOutputAt: 0, now: 5), "Short pause keeps the warm graph")
precondition(!admitted(flat, hasMember: true, lastOutputAt: 0, now: 10), "Long pause releases a sound-neutral graph")
precondition(!admitted(flat), "Idle sound-neutral app is not tapped")
store.configurations["player"]?.isEnabled = true
store.configurations["player"]?.normalizedGains[4] = 6
let filtered = makeTarget(store)
precondition(filtered.equalizerGains?[4] == 6 && !filtered.isSoundNeutralWarm)
precondition(admitted(filtered, hasMember: true, lastOutputAt: 0, now: 100), "Audible EQ keeps its graph while paused")
precondition(admitted(filtered, outputting: true) == admitted(flat, outputting: true), "Preset changes while playing keep graph membership")
store.configurations["player"] = Configuration()
precondition(admitted(makeTarget(store, volume: 0.5)),
             "Non-unity volume is never released as neutral")
store.isFeatureActive = false
let disabled = makeTarget(store)
precondition(!admitted(disabled, hasMember: true, outputting: true), "Global disable or lost access releases idle EQ graphs")
precondition(admitted(disabled, metering: true), "Visible spectrum still admits a bypassed graph")
print("EQ readiness: untouched apps, saved Flat while playing/paused, spectrum visibility, preset changes and global disable passed.")
'''
(out / 'Tests.swift').write_text(target + policy + source)
PY
xcrun swiftc -module-cache-path "$TEST_DIR/ModuleCache" "$TEST_DIR/Tests.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
