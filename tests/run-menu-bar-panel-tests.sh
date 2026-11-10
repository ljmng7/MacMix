#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL_TEST_DIR="$(mktemp -d /tmp/macmix-panel-tests.XXXXXX)"
trap 'rm -rf "$PANEL_TEST_DIR"' EXIT
TARGET="$(uname -m)-apple-macos14.4"
xcrun swiftc -parse-as-library -target "$TARGET" -module-cache-path "$PANEL_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/App/MenuBarPanelPlacement.swift" \
  "$ROOT/tests/MenuBarPanelPlacementTests.swift" -o "$PANEL_TEST_DIR/placement"
"$PANEL_TEST_DIR/placement"
xcrun swiftc -parse-as-library -target "$TARGET" -module-cache-path "$PANEL_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/App/MenuBarPanelViewport.swift" \
  "$ROOT/tests/MenuBarPanelViewportTests.swift" -o "$PANEL_TEST_DIR/viewport"
"$PANEL_TEST_DIR/viewport"
xcrun swiftc -parse-as-library -target "$TARGET" -module-cache-path "$PANEL_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/App/MenuBarPanelPlacement.swift" \
  "$ROOT/MacMix/App/MenuBarPanelCoordinator.swift" \
  "$ROOT/tests/MenuBarPanelCoordinatorTests.swift" -o "$PANEL_TEST_DIR/coordinator"
"$PANEL_TEST_DIR/coordinator"
