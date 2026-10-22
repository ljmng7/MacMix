#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-media-liveness.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$ROOT" "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
source = (root / 'Packages/MediaRemoteAdapter/Sources/CIMediaRemote/MediaRemoteAdapter.m').read_text()
start = source.index('static BOOL processIsRunning(pid_t pid) {')
function = source[start:source.index('\n}\n', start) + 3]
prelude = '#include <errno.h>\n#include <signal.h>\n#include <stdbool.h>\ntypedef bool BOOL;\n'
(out / 'tests.c').write_text(prelude + function + (root / 'tests/MediaSessionLivenessTests.c').read_text())
PY
xcrun clang -Wall -Werror "$TEST_DIR/tests.c" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
