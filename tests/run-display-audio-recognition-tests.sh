#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
display_test_dir="$(mktemp -d /tmp/macmix-display-recognition.XXXXXX)"
trap 'rm -rf "$display_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$display_test_dir/ModuleCache" \
  MacMix/Devices/DisplayAudioDeviceRecognition.swift tests/DisplayAudioDeviceRecognitionTests.swift \
  -o "$display_test_dir/tests"
"$display_test_dir/tests"
