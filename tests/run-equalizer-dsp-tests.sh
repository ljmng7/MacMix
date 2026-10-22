#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EQ_TEST_DIR="$(mktemp -d /tmp/macmix-eq-tests.XXXXXX)"
trap 'rm -rf "$EQ_TEST_DIR"' EXIT
# Set EQ_SANITIZERS=thread to also exercise the parameter mailbox under TSan.
SANITIZERS="${EQ_SANITIZERS:-address,undefined}"
xcrun clang -std=c11 -O1 -g -Wall -Wextra -Werror "-fsanitize=$SANITIZERS" \
  "$ROOT/tests/AppEqualizerDSPTests.c" \
  "$ROOT/Packages/MacMixStudio/Sources/MacMixEQDSP/MacMixEQDSP.c" \
  "$ROOT/MacMix/MacMixAudioIOProc.c" \
  -I "$ROOT/Packages/MacMixStudio/Sources/MacMixEQDSP/include" -I "$ROOT/MacMix" \
  -framework Accelerate -framework CoreAudio -o "$EQ_TEST_DIR/tests"
"$EQ_TEST_DIR/tests"
