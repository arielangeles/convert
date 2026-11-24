#!/usr/bin/env bash
# Runs the unit tests (Swift Testing). Extra arguments go to `swift test`, e.g. --filter Markdown.
#
# With Command Line Tools only (no Xcode), SwiftPM's default build system can fail to load the
# Swift Testing macro plugin ("plugin for module 'TestingMacros' not found"), so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=()
PLUGINS="$(xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing"
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* && -d "$PLUGINS" ]]; then
  ARGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

swift test ${ARGS[@]+"${ARGS[@]}"} "$@"
