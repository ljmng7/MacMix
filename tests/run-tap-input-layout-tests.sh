#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-tap-input-layout.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$ROOT" "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
mixer = (root / 'MacMix/Audio/AppAudioMixer.swift').read_text()
helper = mixer[mixer.index('    struct InputStreamShape'):mixer.index('    private static func outputStreamCandidates')]
(out / 'Tests.swift').write_text('enum Layout {\n' + helper + '}\n' + (root / 'tests/TapInputLayoutTests.swift').read_text())
PY
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/ModuleCache" "$TEST_DIR/Tests.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
