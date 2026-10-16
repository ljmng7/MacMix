#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZERO_TEST_DIR="$(mktemp -d /tmp/macmix-zero-tests.XXXXXX)"
trap 'rm -rf "$ZERO_TEST_DIR"' EXIT
python3 - "$ROOT" "$ZERO_TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
models = (root / 'MacMix/AudioModels.swift').read_text().split('struct NowPlayingItem')[0]
hardware = (root / 'MacMix/CoreAudioHardware.swift').read_text()
controller = hardware[hardware.index('nonisolated struct OutputVolumeSnapshot:'):]
(out / 'Tests.swift').write_text(models + '\n' + controller + '\n' + (root / 'tests/ZeroVolumeTests.swift').read_text())
PY
xcrun swiftc -parse-as-library -module-cache-path "$ZERO_TEST_DIR/ModuleCache" "$ZERO_TEST_DIR/Tests.swift" -o "$ZERO_TEST_DIR/tests"
"$ZERO_TEST_DIR/tests"
