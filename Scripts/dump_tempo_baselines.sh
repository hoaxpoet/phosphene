#!/usr/bin/env bash
# dump_tempo_baselines.sh — DSP.1 reference-track capture driver.
#
# Builds TempoDumpRunner, runs it once per reference track, then
# concatenates the per-track outputs into docs/diagnostics/DSP.1-<phase>.txt
# (where <phase> defaults to "baseline" — pass "after" once voting lands).
#
# Audio fixtures are not committed (preview clips are licensed). Drop them
# into Tests/Fixtures/tempo/ locally or override paths via env vars:
#   LOVE_REHAB_FIXTURE=/path/to/love_rehab.m4a
#   SO_WHAT_FIXTURE=/path/to/so_what.m4a
#   THERE_THERE_FIXTURE=/path/to/there_there.m4a
#
# Usage:
#   Scripts/dump_tempo_baselines.sh             # writes DSP.1-baseline.txt
#   Scripts/dump_tempo_baselines.sh after       # writes DSP.1-after.txt

set -euo pipefail

PHASE="${1:-baseline}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/PhospheneEngine"
FIXTURE_DIR="$ENGINE/Tests/Fixtures/tempo"
DIAG_DIR="$ROOT/docs/diagnostics"
RUNNER="$ENGINE/.build/release/TempoDumpRunner"

LOVE_REHAB_FIXTURE="${LOVE_REHAB_FIXTURE:-$FIXTURE_DIR/love_rehab.m4a}"
SO_WHAT_FIXTURE="${SO_WHAT_FIXTURE:-$FIXTURE_DIR/so_what.m4a}"
THERE_THERE_FIXTURE="${THERE_THERE_FIXTURE:-$FIXTURE_DIR/there_there.m4a}"

mkdir -p "$DIAG_DIR"

echo "==> Building TempoDumpRunner (release)"
swift build --package-path "$ENGINE" -c release --product TempoDumpRunner

run_track () {
    local label="$1"
    local fixture="$2"
    local metadata_bpm="${3:-}"
    local out="$DIAG_DIR/DSP.1-$PHASE-$label.txt"

    if [[ ! -f "$fixture" ]]; then
        echo "==> SKIP $label — fixture not found at $fixture"
        return 0
    fi

    echo "==> $label  ($fixture)"
    if [[ -n "$metadata_bpm" ]]; then
        "$RUNNER" \
            --audio-file "$fixture" \
            --label "$label" \
            --out "$out" \
            --metadata-bpm "$metadata_bpm"
    else
        "$RUNNER" \
            --audio-file "$fixture" \
            --label "$label" \
            --out "$out"
    fi
}

# Reference tracks from CLAUDE.md "Validated Onset Counts" table.
# Metadata BPMs are forwarded as hints (no-op until voting lands).
run_track love_rehab   "$LOVE_REHAB_FIXTURE"   125
run_track so_what      "$SO_WHAT_FIXTURE"      136
run_track there_there  "$THERE_THERE_FIXTURE"

# Concatenate into a single artifact for the increment evidence.
COMBINED="$DIAG_DIR/DSP.1-$PHASE.txt"
: > "$COMBINED"
for label in love_rehab so_what there_there; do
    f="$DIAG_DIR/DSP.1-$PHASE-$label.txt"
    if [[ -f "$f" ]]; then
        cat "$f" >> "$COMBINED"
        echo "" >> "$COMBINED"
    fi
done

echo "==> Wrote $COMBINED"
