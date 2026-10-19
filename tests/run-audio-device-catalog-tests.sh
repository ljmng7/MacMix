#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/macmix-catalog-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/catalog" "$TEST_DIR/empty"
cp "$ROOT/MacMix/AudioDeviceCatalog.json" "$TEST_DIR/catalog/"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/AudioDeviceCatalog.swift" "$ROOT/tests/AudioDeviceCatalogTests.swift" \
  -o "$TEST_DIR/tests"
"$TEST_DIR/tests" "$TEST_DIR/catalog" "$TEST_DIR/empty"
