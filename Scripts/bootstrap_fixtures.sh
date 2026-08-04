#!/usr/bin/env bash
# bootstrap_fixtures.sh — restore the gitignored licensed tempo fixtures into
# THIS checkout. Worktrees don't inherit them (.gitignore:57), so a fresh
# worktree's engine suite fails ~21 fixture tests environmentally until this
# runs. CLEAN.5.2.
#
# Prefer a byte-identical copy from the primary checkout (passes the sha256
# exact-bytes test); fall back to re-fetching from the iTunes Search API.
#
# Usage: Scripts/bootstrap_fixtures.sh    (idempotent; no-op if already complete)
#
# RECON.13: the no-op guard used to be `ls -A` — ANY file in the directory meant
# "nothing to do". A tree holding 1 of 3 clips short-circuited to exit 0 and
# looked restored while still failing the tests this exists to unblock. The
# guard now checks the specific files in Scripts/fixtures.manifest, the same
# list link_fixtures.sh and FixtureManifestPresenceGate read. Non-empty is not
# complete — that conflation is the BUG-080 family in one line.
#
# NOTE: prefer Scripts/link_fixtures.sh. It covers the ML weights as well and
# hard-errors on an incomplete source; this script handles tempo clips only.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/PhospheneEngine/Tests/Fixtures/tempo"
MANIFEST="$ROOT/Scripts/fixtures.manifest"

# Any required file absent => there is work to do.
missing=0
if [ -f "$MANIFEST" ]; then
  while IFS= read -r rel; do
    rel="${rel%%#*}"
    rel="$(printf '%s' "$rel" | tr -d '[:space:]')"
    [ -n "$rel" ] || continue
    [ -e "$ROOT/$rel" ] || { missing=$((missing + 1)); echo "==> missing: $rel"; }
  done < "$MANIFEST"
else
  echo "==> WARNING: $MANIFEST not found; falling back to a non-empty-directory check" >&2
  [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ] && missing=0 || missing=1
fi

if [ "$missing" -eq 0 ]; then
  echo "==> all required tempo fixtures present — nothing to do"
  exit 0
fi
echo "==> $missing required fixture(s) missing — restoring"

# Primary checkout = first entry of `git worktree list` (always the main tree).
MAIN="$(git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
SRC="$MAIN/PhospheneEngine/Tests/Fixtures/tempo"

mkdir -p "$DEST"
if [ "$SRC" != "$DEST" ] && [ -n "$(ls -A "$SRC" 2>/dev/null || true)" ]; then
  echo "==> copying tempo fixtures from primary checkout: $SRC"
  cp -R "$SRC/." "$DEST/"
  echo "==> done ($(ls -1 "$DEST" | wc -l | tr -d ' ') files)"
  exit 0
fi

# Reached when this IS the primary (SRC == DEST, nothing to copy from) or the
# primary is itself missing them — either way the network is the only source.
echo "==> no usable copy source; falling back to fetch_tempo_fixtures.sh"
exec "$ROOT/Scripts/fetch_tempo_fixtures.sh"
