#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
symbol_test_dir="$(mktemp -d /tmp/macmix-symbol-tests.XXXXXX)"
trap 'rm -rf "$symbol_test_dir"' EXIT
# Compile the production resolver against simulated symbol sets for older OSes.
sed 's/^import AppKit$/import Foundation/' MacMix/AudioDeviceSFSymbols.swift > "$symbol_test_dir/AudioDeviceSFSymbols.swift"
xcrun swiftc -parse-as-library -module-cache-path "$symbol_test_dir/ModuleCache" \
  "$symbol_test_dir/AudioDeviceSFSymbols.swift" tests/AudioDeviceSFSymbolsTests.swift \
  -o "$symbol_test_dir/tests"
"$symbol_test_dir/tests"
