#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_TEST_DIR="$(mktemp -d /tmp/macmix-identity-tests.XXXXXX)"
trap 'rm -rf "$CACHE_TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$CACHE_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/AudioProcessIdentityCache.swift" "$ROOT/tests/AudioProcessIdentityCacheTests.swift" \
  -o "$CACHE_TEST_DIR/tests"
"$CACHE_TEST_DIR/tests"
