#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIAGNOSTIC_TEST_DIR="$(mktemp -d /tmp/macmix-diagnostic-tests.XXXXXX)"
trap 'rm -rf "$DIAGNOSTIC_TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$DIAGNOSTIC_TEST_DIR/ModuleCache" \
  "$ROOT/MacMix/Diagnostics/DiagnosticAudioConfiguration.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticHeartbeatMonitor.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticTerminationCoordinator.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticLogText.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticLogMigration.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticLog.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticSystemSampler.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticProcessSampler.swift" \
  "$ROOT/MacMix/Diagnostics/DiagnosticFeedbackExporter.swift" \
  "$ROOT/MacMix/Diagnostics/FeedbackMail.swift" \
  "$ROOT/tests/DiagnosticFeedbackTests.swift" -o "$DIAGNOSTIC_TEST_DIR/tests"
"$DIAGNOSTIC_TEST_DIR/tests"
