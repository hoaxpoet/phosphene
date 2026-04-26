#!/usr/bin/env bash
# run_soak_test.sh — Build and run a Phosphene soak test (Increment 7.1).
#
# Usage:
#   ./Scripts/run_soak_test.sh                         # 2-hour run, procedural audio
#   ./Scripts/run_soak_test.sh --duration 300           # 5-minute run
#   ./Scripts/run_soak_test.sh --audio-file /path/to/loop.wav
#
# All unknown flags are forwarded to SoakRunner. Run `--help` to see all options.
#
# Wraps SoakRunner with caffeinate so macOS App Nap doesn't throttle the process
# during long runs. D-060(d): the 2-hour run lives here, not in the test suite.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "▶ Building SoakRunner (release)..."
swift build --package-path "$PKG_DIR" --configuration release --product SoakRunner

RUNNER="$PKG_DIR/.build/release/SoakRunner"

if [[ ! -x "$RUNNER" ]]; then
    echo "✗ SoakRunner binary not found at $RUNNER"
    exit 1
fi

echo "▶ Starting soak test (caffeinate -i prevents App Nap)..."
echo "  Report will be written to ~/Documents/phosphene_soak/<timestamp>/"
echo ""

# caffeinate -i keeps system awake; SoakRunner forwards all remaining args.
caffeinate -i "$RUNNER" "$@"

echo ""
echo "✓ Soak test complete."
