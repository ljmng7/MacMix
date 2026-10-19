#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-process-owner-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/AudioProcessOwner.swift" "$ROOT/tests/AudioProcessOwnerTests.swift" \
  -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
