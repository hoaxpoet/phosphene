#!/usr/bin/env bash
# check_lfs_smudged.sh — CLEAN.5.4d
#
# Fail LOUD if any Git-LFS-tracked file is still a pointer (the checkout didn't
# smudge). A pointer-file build silently bundles ~130-byte text stubs in place
# of the ML weights (PhospheneEngine/Sources/ML/Weights/**/*.bin) and "passes".
# CLEAN.0 no-silent-skip: resource-absence must FAIL, on CI and a dev box alike.
# Run before the build (cheap; one `git lfs ls-files`).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

command -v git-lfs >/dev/null 2>&1 || {
  echo "FAIL (CLEAN.5.4d): git-lfs not installed — LFS files would be pointer stubs." >&2
  exit 1
}

# Scope to the ML weights only (CLEAN.5.8): CI pulls weights-only to stay under the
# LFS bandwidth quota (ci.yml: `git lfs pull --include=…/Weights/**`), deliberately
# leaving the reel / visual-reference images as pointers. The weights are what the
# build bundles, so they're the only thing this gate must prove smudged. A local
# full checkout smudges everything, so the scope is a no-op there.
weights='PhospheneEngine/Sources/ML/Weights/**'

# `git lfs ls-files` column 2: '*' = object present/smudged, '-' = pointer only.
pointers=$(git lfs ls-files -I "$weights" | awk '$2 == "-"')
if [ -n "$pointers" ]; then
  echo "FAIL (CLEAN.5.4d): ML-weight LFS files un-smudged (still pointers) — run 'git lfs pull --include=\"$weights\"':" >&2
  echo "$pointers" >&2
  exit 1
fi

echo "OK (CLEAN.5.4d): all $(git lfs ls-files -I "$weights" | wc -l | tr -d ' ') ML-weight LFS files smudged."
