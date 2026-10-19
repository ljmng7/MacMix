#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIRPLAY_TEST_DIR="$(mktemp -d /tmp/macmix-airplay-tests.XXXXXX)"
trap 'rm -rf "$AIRPLAY_TEST_DIR"' EXIT
python3 - "$ROOT" "$AIRPLAY_TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
routes = (root / 'MacMix/AirPlayAudioRoutes.swift').read_text()
models = (root / 'MacMix/AudioModels.swift').read_text()
model = (root / 'MacMix/AudioModel.swift').read_text()
device = models[models.index('struct AudioDevice:'):models.index('struct AudioApp:')]
state = model[model.index('@MainActor\n@Observable\nfinal class OutputAudioState'):model.index('@MainActor\n@Observable\nfinal class InputAudioState')]
tests = (root / 'tests/AirPlayAudioRoutesTests.swift').read_text()
hardware = (root / 'MacMix/CoreAudioHardware.swift').read_text()
destinations = hardware[hardware.index('    func airPlayDestinations'):hardware.index('    nonisolated func defaultDeviceID')]
(out / 'Tests.swift').write_text(tests + '\n' + routes + '\n' + device + '\n' + state
    + '\nstruct CoreAudioHardware {\n' + destinations + '\n}\n')
PY
xcrun swiftc -parse-as-library -module-cache-path "$AIRPLAY_TEST_DIR/ModuleCache" \
  "$AIRPLAY_TEST_DIR/Tests.swift" -o "$AIRPLAY_TEST_DIR/tests"
"$AIRPLAY_TEST_DIR/tests"
