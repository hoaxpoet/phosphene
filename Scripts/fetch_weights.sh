#!/usr/bin/env bash
# fetch_weights.sh — fetch the ML weights bundle (PUB.1, Decision 2).
#
# The ~167 MB of stem-separation / beat-tracking / instrument-family weights
# ship as a GitHub Release asset rather than git-LFS content, so cloning the
# repo does not burn LFS bandwidth. This script is idempotent:
#
#   1. If PhospheneEngine/Sources/ML/Weights already verifies against its
#      committed SHA256SUMS manifest, it exits 0 without touching the network
#      (a maintainer checkout, or a re-run).
#   2. Otherwise it downloads ml-weights.tar.gz from the release URL, verifies
#      the archive checksum, unpacks, and re-verifies every file.
#
# Override the source with PHOSPHENE_WEIGHTS_URL (e.g. a mirror or a local
# file:// path). The expected archive checksum lives next to the asset as
# ml-weights.tar.gz.sha256 and is fetched from the same base URL.
#
# Usage: Scripts/fetch_weights.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEIGHTS_DIR="$REPO_ROOT/PhospheneEngine/Sources/ML/Weights"
MANIFEST="$WEIGHTS_DIR/SHA256SUMS"
DEFAULT_URL="https://github.com/hoaxpoet/phosphene/releases/download/ml-weights-v1/ml-weights.tar.gz"
URL="${PHOSPHENE_WEIGHTS_URL:-$DEFAULT_URL}"

[ -f "$MANIFEST" ] || { echo "fetch_weights: missing $MANIFEST — repo checkout is broken" >&2; exit 1; }

verify() {
  # shasum -c is quiet on success; returns non-zero on any mismatch/missing file.
  (cd "$WEIGHTS_DIR" && shasum -a 256 -c SHA256SUMS --quiet) 2>/dev/null
}

if verify; then
  echo "fetch_weights: weights present and verified ($(wc -l < "$MANIFEST" | tr -d ' ') files) — nothing to do"
  exit 0
fi

echo "fetch_weights: weights missing or stale — fetching $URL"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fSL --retry 3 -o "$TMP/ml-weights.tar.gz" "$URL"
curl -fSL --retry 3 -o "$TMP/ml-weights.tar.gz.sha256" "$URL.sha256"
(cd "$TMP" && shasum -a 256 -c ml-weights.tar.gz.sha256 --quiet) \
  || { echo "fetch_weights: archive checksum MISMATCH — refusing to unpack" >&2; exit 1; }

# Archive contains the Weights/ directory contents at its root.
mkdir -p "$WEIGHTS_DIR"
tar -xzf "$TMP/ml-weights.tar.gz" -C "$WEIGHTS_DIR"

verify || { echo "fetch_weights: post-unpack verification FAILED" >&2; exit 1; }
echo "fetch_weights: done — $(wc -l < "$MANIFEST" | tr -d ' ') files verified"
