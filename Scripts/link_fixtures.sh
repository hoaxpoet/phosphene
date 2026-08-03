#!/usr/bin/env bash
# link_fixtures.sh
#
# Make the gitignored assets a worktree needs runnable inside that worktree.
#
# Several trees are deliberately kept out of git — copyrighted audio fixtures,
# ML weights (shipped as the `ml-weights-v1` Release asset since PUB.2), and
# reference/diagnostic images (untracked since the LFS cutover, D-211). Git
# worktrees and fresh clones never receive any of them, so the tests and the
# preset workflow that depend on them fail — or silently degrade — in a
# worktree. See memory `project_worktree_engine_fixtures_absent`.
#
# This symlinks each such gitignored file from the PRIMARY checkout (the main
# worktree) into the current worktree. Idempotent; a no-op on the primary and
# for files already present.
#
# BUG-080 (2026-08-03) — two failures this script previously had, both fixed here:
#
#   Gap A: the ML weights were never in the list, AND the match filter admitted
#     only Tests/Fixtures paths or jpg/jpeg/png/gif, so a `.bin` could not pass
#     even once the directory was added. 479 files never reached a worktree.
#
#   Gap B, the deeper one: this script trusted the primary checkout to be a
#     COMPLETE source and never verified it. `Tests/Fixtures/tempo/` was absent
#     from the primary entirely — the clips lived only inside one other
#     worktree — so no worktree could obtain them, the primary failed the same
#     gate, and this script reported success while propagating the hole.
#     A `required` flag now makes an empty source tree a HARD ERROR.
#
# The rule this encodes: a preparation script that cannot supply what it
# promises must fail loudly, never report success. Same philosophy as
# BeatThisFixturePresenceGate (QR.3), which is what caught Gap B.
#
# Usage:
#   Scripts/link_fixtures.sh            run once after `git worktree add`
#   Scripts/link_fixtures.sh --verify   check the PRIMARY is a complete source
#                                       and exit non-zero if not; links nothing.
#                                       Runnable from the primary itself.

set -uo pipefail

mode="${1:-link}"
case "$mode" in
  link|--verify) ;;
  *) echo "link_fixtures: unknown argument '$mode' (expected --verify or nothing)" >&2; exit 2 ;;
esac

repo_root="$(git rev-parse --show-toplevel)" || { echo "link_fixtures: not in a git repo" >&2; exit 1; }
# The primary (main) worktree is the first entry of `git worktree list`.
primary="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

# ---------------------------------------------------------------------------
# The manifest: gitignored-but-needed paths.
#
#   <path>|<required>|<match-regex>
#
#   required=yes  the primary MUST hold at least one matching gitignored file.
#                 An empty tree is a hard error — that is Gap B.
#   required=no   nice-to-have; absence degrades work but does not fail a run.
#
#   match-regex   filters what is worth linking. The docs trees also collect OS
#                 junk (.DS_Store) that would otherwise be symlinked into every
#                 worktree, so they are restricted to rasters.
#
# Keep this list in sync with the Swift presence gates
# (BeatThisFixturePresenceGate). A single shared manifest consumed by both is
# the remaining BUG-080 follow-up; until then, changes here need a look there.
# ---------------------------------------------------------------------------
manifest=(
  "PhospheneEngine/Tests/Fixtures|yes|."
  "PhospheneEngine/Sources/ML/Weights|yes|."
  "docs/VISUAL_REFERENCES|no|\.(jpg|jpeg|png|gif)$"
  "docs/diagnostics|no|\.(jpg|jpeg|png|gif)$"
)

# `git ls-files --others --ignored --exclude-standard` lists exactly the
# gitignored (untracked-and-ignored) files under a path — the set that never
# reaches a worktree.
source_files() {   # $1 = path, $2 = regex
  (cd "$primary" && git ls-files --others --ignored --exclude-standard -- "$1" 2>/dev/null) \
    | grep -E "$2" || true
}

# --- Source completeness check (Gap B) — runs in BOTH modes ----------------
incomplete=0
for entry in "${manifest[@]}"; do
  IFS='|' read -r path required regex <<< "$entry"
  count="$(source_files "$path" "$regex" | grep -c . || true)"
  if [ "$required" = "yes" ] && [ "$count" -eq 0 ]; then
    echo "link_fixtures: ERROR — required tree is EMPTY in the primary checkout:" >&2
    echo "                 $primary/$path" >&2
    echo "                 Nothing can be linked from it, and the primary itself will fail" >&2
    echo "                 its presence gate. Restore the files there first (they are" >&2
    echo "                 gitignored, so they must be copied in by hand or re-downloaded)." >&2
    incomplete=1
  elif [ "$required" != "yes" ] && [ "$count" -eq 0 ]; then
    # Not fatal, but never silent: D-211's whole point is that a worktree
    # missing the reference images degrades preset work rather than failing.
    echo "link_fixtures: WARNING — optional tree is empty in the primary: $path" >&2
    echo "                 (preset work that depends on it will silently degrade)" >&2
    [ "$mode" = "--verify" ] && printf 'link_fixtures: %-40s %5s file(s)\n' "$path" "$count"
  elif [ "$mode" = "--verify" ]; then
    printf 'link_fixtures: %-40s %5s file(s)%s\n' "$path" "$count" \
      "$([ "$required" = "yes" ] && echo "  [required]" || echo "")"
  fi
done

if [ "$incomplete" -ne 0 ]; then
  echo "link_fixtures: FAILED — the primary checkout is not a complete source (BUG-080 Gap B)." >&2
  exit 1
fi

if [ "$mode" = "--verify" ]; then
  echo "link_fixtures: primary checkout is a complete source."
  exit 0
fi

if [ "$repo_root" = "$primary" ]; then
  echo "link_fixtures: already in the primary checkout ($primary) — nothing to link."
  exit 0
fi

# --- Link ------------------------------------------------------------------
linked=0
missing=0
for entry in "${manifest[@]}"; do
  IFS='|' read -r path required regex <<< "$entry"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$primary/$rel"
    dst="$repo_root/$rel"
    if [ ! -e "$src" ]; then
      # Listed by git but absent on disk — report it; never skip in silence.
      echo "link_fixtures: WARNING — listed but missing from primary: $rel" >&2
      missing=$((missing + 1))
      continue
    fi
    [ -e "$dst" ] && continue      # already here (real file or prior link)
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    linked=$((linked + 1))
  done < <(source_files "$path" "$regex")
done

echo "link_fixtures: $linked file(s) linked into $(basename "$repo_root") from $(basename "$primary")."
if [ "$missing" -ne 0 ]; then
  echo "link_fixtures: $missing file(s) were listed by git but absent on disk — see warnings above." >&2
  exit 1
fi
