#!/usr/bin/env bash
# check_design_token_drift.sh — DS.1 / D-231.
#
# `UzumeApp/DesignSystem/UzumeTokens.swift` is a vendored copy of the design
# system's token file (D-228: uzume-site owns the design system, the app only
# consumes it). Vendoring keeps a fresh clone and CI single-repo, at the cost of
# a manual re-sync. This script is what makes the cost visible:
#
#   1. The vendored body must still hash to the SHA-256 recorded in its header.
#      Always checked — this catches an edit to the vendored copy.
#   2. The upstream file must still hash to the same value. Checked only when a
#      sibling `uzume-site` checkout is present — this catches upstream moving on.
#      No sibling → prints SKIP and exits 0, so fresh clones and CI stay green.
#
# Usage: Scripts/check_design_token_drift.sh   (no arguments; runnable from anywhere)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDORED="$REPO_ROOT/UzumeApp/DesignSystem/UzumeTokens.swift"
MARKER='// --- BEGIN VENDORED CONTENT'
UPSTREAM_REL='DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift'

if [ ! -f "$VENDORED" ]; then
  echo "FAIL — vendored token file missing: $VENDORED"
  exit 1
fi

RECORDED="$(sed -n 's|^// *SHA-256: *\([0-9a-f]\{64\}\).*|\1|p' "$VENDORED" | head -1)"
if [ -z "$RECORDED" ]; then
  echo "FAIL — no SHA-256 provenance line in $VENDORED"
  exit 1
fi

# 1. Vendored body — everything after the BEGIN marker line.
ACTUAL="$(awk -v m="$MARKER" 'f{print} index($0,m)==1{f=1}' "$VENDORED" | shasum -a 256 | cut -d' ' -f1)"
if [ "$ACTUAL" != "$RECORDED" ]; then
  echo "FAIL — vendored token body was edited."
  echo "  recorded: $RECORDED"
  echo "  actual:   $ACTUAL"
  echo "  The vendored copy is byte-identical-to-upstream by contract. Put app-only"
  echo "  roles in UzumeApp/DesignSystem/UzumeTokens+App.swift instead."
  exit 1
fi

# 2. Upstream — only if a sibling checkout is present. The worktree case needs the
#    primary checkout's parent, since a worktree root sits under .claude/worktrees/.
PRIMARY_ROOT="$(cd "$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)"
SIBLING=""
for candidate in "$REPO_ROOT/../uzume-site" "${PRIMARY_ROOT:-/nonexistent}/../uzume-site"; do
  if [ -f "$candidate/$UPSTREAM_REL" ]; then
    SIBLING="$(cd "$candidate" && pwd)"
    break
  fi
done

if [ -z "$SIBLING" ]; then
  echo "SKIP — no sibling uzume-site checkout; vendored body verified against its recorded hash."
  exit 0
fi

UPSTREAM_HASH="$(shasum -a 256 "$SIBLING/$UPSTREAM_REL" | cut -d' ' -f1)"
if [ "$UPSTREAM_HASH" != "$RECORDED" ]; then
  echo "FAIL — upstream design tokens have moved on."
  echo "  vendored (uzume-site@$(sed -n 's|^// *Source commit: *||p' "$VENDORED" | head -1)): $RECORDED"
  echo "  upstream ($SIBLING): $UPSTREAM_HASH"
  echo "  Re-vendor: copy the upstream file, update the header commit + SHA-256, and"
  echo "  re-check every role in UzumeTokens+App.swift against tokens.css."
  exit 1
fi

echo "OK — vendored tokens match uzume-site@$(sed -n 's|^// *Source commit: *||p' "$VENDORED" | head -1) ($RECORDED)"
exit 0
