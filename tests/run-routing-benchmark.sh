#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$(mktemp -d /tmp/macmix-routing-bench.XXXXXX)"
trap 'rm -rf "$BENCH_DIR"' EXIT
xcrun clang -O2 -std=c11 "$ROOT/tests/AudioRoutingBenchmark.c" \
  "$ROOT/MacMix/MacMixAudioIOProc.c" "$ROOT/Packages/MacMixStudio/Sources/MacMixEQDSP/MacMixEQDSP.c" \
  -I "$ROOT/MacMix" -I "$ROOT/Packages/MacMixStudio/Sources/MacMixEQDSP/include" \
  -framework CoreAudio -framework Accelerate -o "$BENCH_DIR/benchmark"
"$BENCH_DIR/benchmark"
