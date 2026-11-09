#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCK_TEST_DIR="$(mktemp -d /tmp/macmix-dock-tests.XXXXXX)"
trap 'rm -rf "$DOCK_TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$DOCK_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/App/ApplicationDockVisibility.swift" \
  "$ROOT/tests/DockVisibilityTests.swift" -o "$DOCK_TEST_DIR/tests"
"$DOCK_TEST_DIR/tests"
