#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
export GIMME_PANEL_CHECK_OUTPUT="${GIMME_PANEL_CHECK_OUTPUT:-$TEMP/screenshots}"
mkdir -p "$GIMME_PANEL_CHECK_OUTPUT"
{
  swiftc -swift-version 6 -parse-as-library \
    "$ROOT/mac/Sources/GimmeRemote/MenuPanel.swift" "$ROOT/scripts/menu-panel-checks.swift" \
    -module-cache-path "$TEMP/module-cache" -o "$TEMP/menu-panel-checks"
  "$TEMP/menu-panel-checks"
} 2>&1 | tee "$GIMME_PANEL_CHECK_OUTPUT/checks.log"
