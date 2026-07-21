#!/usr/bin/env bash
# Purge docs/VISUAL_REFERENCES + docs/diagnostics images from LFS history.
# Runs against a FRESH MIRROR CLONE — your working checkout is never touched.
# Does NOT push unless you pass --execute. Review the dry-run first.
#
# What this does NOT fix on its own: GitHub does not garbage-collect LFS
# objects on push. After the force-push, the old blobs still occupy LFS
# storage (and keep billing) until GitHub GCs them — which today means
# opening a GitHub Support request to purge unreferenced LFS objects, or
# deleting+recreating the repo. The rewrite is the prerequisite; the reclaim
# is that follow-up. Budget for it.
set -euo pipefail

REMOTE="https://github.com/hoaxpoet/phosphene.git"
WORK="${TMPDIR:-/tmp}/phosphene-lfs-purge"
# Purge ONLY raster images under these dirs. Text records (READMEs, diagnoses,
# rendering contracts, source_*.txt/json) live here too and MUST survive.
IMG_REGEX='docs/(VISUAL_REFERENCES|diagnostics)/.*\.(jpg|jpeg|png|gif)$'
EXECUTE=0
[[ "${1:-}" == "--execute" ]] && EXECUTE=1

echo "== Fresh mirror clone → $WORK =="
rm -rf "$WORK"
git clone --mirror "$REMOTE" "$WORK"
cd "$WORK"

echo "== LFS images BEFORE (unique objects referenced by history) =="
git lfs ls-files --all | grep -E 'VISUAL_REFERENCES|diagnostics' | wc -l | xargs echo "  image files to remove:"

echo "== Rewriting history: dropping matching images from every commit =="
# --invert-paths + --path-regex removes ONLY files matching IMG_REGEX; every
# other blob (incl. the text records in these dirs) stays byte-identical.
git filter-repo --force \
  --path-regex "$IMG_REGEX" \
  --invert-paths

# filter-repo strips the remote as a safety measure; restore it.
git remote add origin "$REMOTE" 2>/dev/null || git remote set-url origin "$REMOTE"

echo "== Verify: no image blobs remain under those dirs in ANY history =="
if git log --all --name-only --pretty=format: -- 'docs/VISUAL_REFERENCES' 'docs/diagnostics' \
     | grep -iE '\.(jpg|jpeg|png|gif)$' | grep -q .; then
  echo "  !! images still present — aborting"; exit 1
else
  echo "  OK: 0 image blobs remain"
fi
echo "== Sanity: a known text record SURVIVED the rewrite =="
git cat-file -e HEAD:docs/diagnostics/CODE_AUDIT_2026-06-13.md \
  && echo "  OK: CODE_AUDIT_2026-06-13.md still in tree" \
  || { echo "  !! text record lost — aborting"; exit 1; }
echo "== Remaining LFS files (should be weights only) =="
git lfs ls-files --all | sed -E 's#([^/]+/[^/]+)/.*#\1#' | sort | uniq -c

if [[ $EXECUTE -eq 0 ]]; then
  cat <<EOF

== DRY RUN complete. Nothing pushed. ==
Rewritten mirror is at: $WORK
To actually publish (rewrites shared history on origin — coordinate first):
  bash $0 --execute
EOF
  exit 0
fi

echo "== FORCE-PUSHING rewritten history to origin =="
read -r -p "Type 'push' to force-push all refs to $REMOTE: " ans
[[ "$ans" == "push" ]] || { echo "aborted"; exit 1; }
git push --force --mirror origin
echo "== Done. Now: (1) every other clone must re-clone, (2) open a GitHub"
echo "   Support request to GC unreferenced LFS objects to reclaim storage. =="
