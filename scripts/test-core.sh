#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
# Apple's standalone Command Line Tools do not ship the Testing module.
# Run critical core checks without Xcode, while CI runs the full Swift Testing suite.
swiftc -swift-version 6 -parse-as-library \
  "$ROOT"/mac/Sources/RemoteCore/*.swift "$ROOT/scripts/core-checks.swift" \
  -module-cache-path "$TEMP/module-cache" -o "$TEMP/core-checks"
"$TEMP/core-checks"
