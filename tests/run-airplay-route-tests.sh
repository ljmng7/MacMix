#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIRPLAY_TEST_DIR="$(mktemp -d /tmp/macmix-airplay-tests.XXXXXX)"
trap 'rm -rf "$AIRPLAY_TEST_DIR"' EXIT
python3 - "$ROOT" "$AIRPLAY_TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
routes = (root / 'MacMix/Devices/AirPlayAudioRoutes.swift').read_text()
models = (root / 'MacMix/Audio/AudioModels.swift').read_text()
model = (root / 'MacMix/Audio/AudioModel.swift').read_text()
device = models[models.index('struct AudioDevice:'):models.index('struct AudioApp:')]
state = model[model.index('@MainActor\n@Observable\nfinal class OutputAudioState'):model.index('@MainActor\n@Observable\nfinal class InputAudioState')]
store = (root / 'Packages/MacMixStudio/Sources/MacMixStudio/AppOutputRouting.swift').read_text()
tests = (root / 'tests/AirPlayAudioRoutesTests.swift').read_text()
hardware = (root / 'MacMix/Audio/CoreAudioHardware.swift').read_text()
destinations = hardware[hardware.index('    func airPlayDestinations'):hardware.index('    nonisolated func defaultDeviceID')]
mixer = (root / 'MacMix/Audio/AppAudioMixer.swift').read_text()
silence = mixer[mixer.index('    nonisolated func silenceChangedAirPlayReceivers'):mixer.index('    private var routingTapIndices')]
mask = mixer[mixer.index('    private func destinationMask'):mixer.index('    private struct OutputStreamCandidate')]
(out / 'Tests.swift').write_text(tests + '\n' + routes + '\n' + device + '\n' + store + '\n' + state
    + '\nstruct CoreAudioHardware {\n' + destinations + '\n}\n'
    + '\nfinal class RunningMixerMaskProbe {\n'
    + '    var usesOutputRouting = true\n    var audioIOContext: Int? = 1\n'
    + '    var outputRoutes: [String: [String]] = ["music": ["local", "airplay-hal"]]\n'
    + '    var airPlayRoutes = ["airplay-hal": AirPlayOutputRoute(deviceID: 100, sourceIDs: [7])]\n'
    + '    var routingTapIndices = ["music": 0]\n    var routedPhysicalUIDs = ["local", "airplay-hal"]\n'
    + silence + mask + '\n}\n')
PY
xcrun swiftc -parse-as-library -module-cache-path "$AIRPLAY_TEST_DIR/ModuleCache" \
  "$AIRPLAY_TEST_DIR/Tests.swift" -o "$AIRPLAY_TEST_DIR/tests"
"$AIRPLAY_TEST_DIR/tests"
