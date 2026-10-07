#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DDC_TEST_DIR="$(mktemp -d /tmp/macmix-ddc-tests.XXXXXX)"
trap 'rm -rf "$DDC_TEST_DIR"' EXIT
python3 - "$ROOT" "$DDC_TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
protocol = (root / 'MacMix/DDCProtocol.swift').read_text()
controller = (root / 'MacMix/DisplayVolumeController.swift').read_text()
if sys.platform != 'darwin':
    # Keep the actual queue, routing, caching and mute/write implementation.
    # Only platform imports and IOKit transports need substitutes on Linux.
    controller = controller.split('\n#if arch(arm64)\n\nprivate typealias IOAVServiceRef')[0]
    controller = controller.replace('import CoreAudio\n', '').replace('import CoreGraphics\n', '')
    controller = controller.replace('import IOKit\n', '').replace('import IOKit.i2c\n', '')
    controller += '''
typealias CGDirectDisplayID = UInt32
let kAudioDeviceTransportTypeHDMI: UInt32 = 1
let kAudioDeviceTransportTypeDisplayPort: UInt32 = 2
let kAudioDeviceTransportTypeThunderbolt: UInt32 = 3
nonisolated final class IntelDDCTransport: DDCTransport {
    init?(displayID: CGDirectDisplayID) { return nil }
    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? { nil }
    func write(command: UInt8, value: UInt16) -> Bool { false }
}
nonisolated enum Arm64DDCTransport {
    static func transport(for display: ExternalDisplayDescriptor) -> DDCTransport? { nil }
}
'''
(out / 'DDCTests.swift').write_text(protocol + '\n' + controller + '\n' +
                                   (root / 'tests/DDCVolumeTests.swift').read_text())
PY
if [[ "$(uname -s)" == Darwin ]]; then
  xcrun swiftc -parse-as-library -module-cache-path "$DDC_TEST_DIR/ModuleCache" \
    "$DDC_TEST_DIR/DDCTests.swift" -o "$DDC_TEST_DIR/tests"
else
  "${SWIFTC:-swiftc}" -parse-as-library -module-cache-path "$DDC_TEST_DIR/ModuleCache" \
    "$DDC_TEST_DIR/DDCTests.swift" -o "$DDC_TEST_DIR/tests"
fi
"$DDC_TEST_DIR/tests"

