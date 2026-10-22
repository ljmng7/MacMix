#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
speaker_test_dir="$(mktemp -d /tmp/macmix-speaker-icons.XXXXXX)"
trap 'rm -rf "$speaker_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$speaker_test_dir/ModuleCache" \
  MacMix/Devices/MacBuiltInSpeakerIcon.swift tests/MacBuiltInSpeakerIconTests.swift \
  -o "$speaker_test_dir/tests"
"$speaker_test_dir/tests"
