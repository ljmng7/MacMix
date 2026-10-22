#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOLUME_TEST_DIR="$(mktemp -d /tmp/macmix-device-volume-tests.XXXXXX)"
trap 'rm -rf "$VOLUME_TEST_DIR"' EXIT
# Compile the actual scheduler.
cat "$ROOT/MacMix/RoutedDeviceVolume.swift" > "$VOLUME_TEST_DIR/VolumeTests.swift"
cat "$ROOT/tests/RoutedDeviceVolumeSchedulerTests.swift" >> "$VOLUME_TEST_DIR/VolumeTests.swift"
xcrun swiftc -parse-as-library -module-cache-path "$VOLUME_TEST_DIR/ModuleCache" \
  "$VOLUME_TEST_DIR/VolumeTests.swift" -o "$VOLUME_TEST_DIR/tests"
"$VOLUME_TEST_DIR/tests"
