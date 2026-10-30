#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
nearby_test_dir="$(mktemp -d /tmp/macmix-nearby-accessories.XXXXXX)"
trap 'rm -rf "$nearby_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$nearby_test_dir/ModuleCache" \
  MacMix/Devices/NearbyAudioAccessories.swift tests/NearbyAudioAccessoryTests.swift \
  -o "$nearby_test_dir/tests"
"$nearby_test_dir/tests"
