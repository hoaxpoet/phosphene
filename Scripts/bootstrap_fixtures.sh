#!/usr/bin/env bash
# bootstrap_fixtures.sh — restore the gitignored licensed tempo fixtures into
# THIS checkout. Worktrees don't inherit them (.gitignore:57), so a fresh
# worktree's engine suite fails ~21 fixture tests environmentally until this
# runs. CLEAN.5.2.
#
# Prefer a byte-identical copy from the primary checkout (passes the sha256
# exact-bytes test); fall back to re-fetching from the iTunes Search API.
#
# Usage: Scripts/bootstrap_fixtures.sh    (idempotent; no-op if already present)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/PhospheneEngine/Tests/Fixtures/tempo"

if [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ]; then
  echo "==> tempo fixtures already present in $DEST — nothing to do"
  exit 0
fi

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

echo "==> primary checkout has no fixtures; falling back to fetch_tempo_fixtures.sh"
exec "$ROOT/Scripts/fetch_tempo_fixtures.sh"
