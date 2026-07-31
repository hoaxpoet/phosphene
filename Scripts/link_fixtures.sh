#!/usr/bin/env bash
# link_fixtures.sh
#
# Make the gitignored test fixtures runnable inside a git worktree.
#
# The engine test fixtures under PhospheneEngine/Tests/Fixtures (the tempo/
# audio clips) are gitignored — they are copyrighted and deliberately kept out
# of history. Git worktrees and fresh clones therefore never receive them, so
# the fixture-dependent engine tests (BeatThisFixturePresenceGate + everything
# downstream) fail environmentally in a worktree. See memory
# `project_worktree_engine_fixtures_absent`.
#
# This symlinks each such gitignored fixture from the PRIMARY checkout (the main
# worktree) into the current worktree, so `swift test --package-path
# PhospheneEngine` runs the full suite. Idempotent; a no-op on the primary
# checkout and for fixtures already present.
#
# ponytail: symlinks, not copies — no duplicated audio, always current. Ceiling:
# links break if the primary checkout moves/is deleted; re-run to repair, or copy
# instead if you need the worktree self-contained.
#
# Usage: Scripts/link_fixtures.sh    (run once after `git worktree add`)

set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)" || { echo "link_fixtures: not in a git repo" >&2; exit 1; }
# The primary (main) worktree is the first entry of `git worktree list`.
primary="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

if [ "$repo_root" = "$primary" ]; then
  echo "link_fixtures: already in the primary checkout ($primary) — nothing to do."
  exit 0
fi

# Gitignored-but-needed paths that a fresh worktree would otherwise lack.
#   Fixtures  — engine tests read them; ~21 tests fail environmentally without.
#   Reference/diagnostic IMAGES — gitignored since the LFS cutover, and the
#     preset-session workflow is "read the README and LOOK at the images", so a
#     worktree without them silently degrades preset work rather than failing.
linked_rel=(
  "PhospheneEngine/Tests/Fixtures"
  "docs/VISUAL_REFERENCES"
  "docs/diagnostics"
)
linked=0

# `git ls-files --others --ignored --exclude-standard` lists exactly the
# gitignored (untracked-and-ignored) files under the path — the set that never
# reaches a worktree.
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$primary/$rel"
  dst="$repo_root/$rel"
  [ -e "$src" ] || continue      # gone from primary — skip
  [ -e "$dst" ] && continue      # already here (real file or prior link)
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "linked $rel"
  linked=$((linked + 1))
# Filter to things worth linking: everything under Tests/Fixtures, but only
# raster images under the docs dirs — those trees also collect OS junk
# (.DS_Store) that would otherwise be symlinked into every worktree.
done < <(cd "$primary" && git ls-files --others --ignored --exclude-standard -- "${linked_rel[@]}" \
         | grep -E '^PhospheneEngine/Tests/Fixtures/|\.(jpg|jpeg|png|gif)$')

echo "link_fixtures: $linked fixture(s) linked into $(basename "$repo_root") from $(basename "$primary")."
