#!/usr/bin/env bash
# Local only: needs a running MacMix (./script/build_and_run.sh) and
# Accessibility permission for the terminal. Not part of CI.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc tests/AccessibilitySmokeTests.swift -o "$test_dir/accessibility-smoke"
"$test_dir/accessibility-smoke" "$PWD/build/DerivedData/Build/Products/Debug/MacMix.app"
