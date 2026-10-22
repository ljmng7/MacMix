#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
symbol_test_dir="$(mktemp -d /tmp/macmix-symbol-tests.XXXXXX)"
trap 'rm -rf "$symbol_test_dir"' EXIT
# Compile the production resolver against simulated symbol sets for older OSes.
python3 - "$symbol_test_dir/AudioDeviceSFSymbols.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('MacMix/BluetoothAudioBattery.swift').read_text()
start = source.index('enum AudioDeviceSFSymbols {')
end = source.index('\nnonisolated private func normalizedAudioAccessoryName', start)
pathlib.Path(sys.argv[1]).write_text(source[start:end])
PY
xcrun swiftc -parse-as-library -module-cache-path "$symbol_test_dir/ModuleCache" \
  "$symbol_test_dir/AudioDeviceSFSymbols.swift" tests/AudioDeviceSFSymbolsTests.swift \
  -o "$symbol_test_dir/tests"
"$symbol_test_dir/tests"
