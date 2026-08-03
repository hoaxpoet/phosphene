# Runbook — reclaiming Git-LFS storage

**Status:** **performed successfully on 2026-08-03** — full record in §9. The earlier attempt on 2026-07-31 half-applied and was reverted; that incident is §8. Keep both: §8 is what going wrong looks like, §9 is what going right looks like, and the whole difference between them is §3 and §4.
**Blast radius:** every clone, every worktree, every open PR, every branch. This is the highest-risk operation in the repo.
**Time:** ~30 min of commands, plus a GitHub Support turnaround measured in days.
**Decision owner:** Matt. Nothing here is routine maintenance.

---

## 1. What this does, and what it does not

Phosphene is billed for Git-LFS **storage** (and historically bandwidth — CLEAN.5.8, where CI checkouts burned 5.5× the 10 GB/mo quota in three days). Two separate things drive the bill, and they need separate fixes:

| | Fix | Status |
|---|---|---|
| **New** LFS objects accumulating | Untrack the files, drop the LFS rules | **Done** — D-211 (images), PUB.2 (weights) |
| **Existing** objects already in history | Rewrite history, then have GitHub purge orphans | **This runbook** |

> **The single most important sentence in this document: rewriting history does not reduce the bill.**
>
> GitHub does not garbage-collect unreferenced LFS objects. After the force-push, every old object still occupies billed storage. The rewrite makes them *unreferenced*; a **GitHub Support request** is what makes them *gone*. If you do the rewrite and stop, you have paid the entire cost of the operation and received none of the benefit.

**Measured payoff** (actual, 2026-08-03): repo `1.4 GB → 82 MB`, 755 LFS objects orphaned, all text records intact. That is a real 94 % reduction — but it is a *repo size* number, not a billing number, and the two move independently. Full record in §9.

---

## 2. Decide the scope first

Do **not** run this twice. Every rewrite orphans every clone, so batching is not an optimisation, it is the difference between one disruption and two.

| Target | Objects | In `IMG_REGEX` today? |
|---|---|---|
| `docs/VISUAL_REFERENCES/**` + `docs/diagnostics/**` rasters | 287 | yes |
| `PhospheneEngine/Sources/ML/Weights/**/*.bin` | **468** | **yes — scope decided 2026-08-02** |
| `docs/quality_reel.mp4` | 1 | no (still legitimately LFS) |
| `PhospheneEngine/Sources/ML/Models/**/*.mlpackage` blobs | 11 | no — live, must survive |

Counts are unique LFS objects referenced by history (`git lfs ls-files --all`), measured 2026-08-02. Earlier drafts said 479 weights; that is the file count on disk, which dedupes to 468 objects. 767 total today, 755 of them targeted.

The weights are the larger object count and almost certainly the larger share of the bill. They are already out of the working tree (PUB.2) and ship as the `ml-weights-v1` Release asset, so **nothing depends on them remaining in history.** This is now applied — `IMG_REGEX` in `Scripts/reclaim-lfs-visual-refs.sh` reads:

```
'(docs/(VISUAL_REFERENCES|diagnostics)/.*\.(jpg|jpeg|png|gif)|PhospheneEngine/Sources/ML/Weights/.*\.bin)$'
```

Verify the new regex against a dry run and confirm `SHA256SUMS` survives — it is the manifest `fetch_weights.sh` verifies against, and losing it breaks every clone's ability to fetch weights. The script now asserts this directly, and aborts if either canary is missing.

Dry run on this scope (2026-08-02): 287 images + 468 weights removed, 0 of either remaining, both canaries intact, 12 LFS objects left (the 11 live `.mlpackage` blobs + `quality_reel.mp4`), repo 1.4 GB → 82 MB.

---

## 3. Pre-flight — all must pass

Nothing below is optional. Item 4 is the one that saved the 2026-07-31 incident.

1. **No in-flight local-only work.** Branches that exist only on a developer machine are orphaned by the rewrite and cannot be recovered by re-cloning. List them:
   ```bash
   git branch --format='%(refname:short) %(upstream)' | awk '$2==""{print $1}'
   ```
   Land, push, or explicitly abandon each. *(At the 2026-07-31 attempt this was `ft3-barline-accents-tasks-bf7b8d` — 4 commits of that day's work — and `ricercar-echo-look-prompt-bd7993` — 26 commits, unpushed.)*

   **That command is not sufficient on its own, and it nearly cost the ft3 work a second time on 2026-08-03.** It filters for branches with *no* upstream, but a branch whose remote was deleted keeps its now-dangling upstream config — so it looks pushed and the filter skips it. `ft3-barline-accents-tasks-bf7b8d` was cleared on that basis, and its 4 commits existed nowhere but one local clone that was about to be deleted for the re-clone. Check for dangling upstreams as well:
   ```bash
   git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads | while read b u; do
     [ -n "$u" ] && ! git rev-parse --verify -q "$u" >/dev/null && echo "DANGLING UPSTREAM: $b (was $u)"
   done
   ```
   Anything listed is local-only regardless of what its config says. Rescue it as patches *before* the rewrite — do not simply push it, because pushing old history re-references the very LFS objects you are trying to orphan:
   ```bash
   git format-patch <merge-base>..<branch> -o ~/phosphene-<branch>-rescue
   ```

2. **No open PRs you intend to merge.** PR head refs are rewritten; `refs/pull/*` are not (GitHub refuses). Merge or close first.

3. **Tooling present.** `git-filter-repo` on PATH, and free space in `TMPDIR` of at least 2× the current `.git`.

4. **Capture every current ref SHA — this is your undo.**
   ```bash
   git ls-remote origin | tee ~/phosphene-refs-before-$(date -u +%Y%m%dT%H%M%SZ).txt
   ```
   Keep it outside the repo. Also confirm the objects exist locally, because that is what recovery actually depends on:
   ```bash
   git fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune
   ```

5. **Branch protection on `main` is the thing that will bite you.** See §4.

---

## 4. The failure mode that already happened once

`Scripts/reclaim-lfs-visual-refs.sh --execute` runs `git push --force --mirror origin`. GitHub evaluates each ref independently:

- **`main` is rejected** (`GH006: protected branch update failed`).
- **`refs/pull/*` are rejected** (`deny updating a hidden ref`).
- **Every other branch and tag succeeds.**

The push reports a non-zero exit, but the successful refs **stay pushed**. The result is a split-brain repo: `main` on old history, every feature branch on a disjoint rewrite sharing no ancestry. Branches read as 1,000–2,000 commits "ahead" of `main` and cannot merge.

**This is the default outcome if you run `--execute` without lifting branch protection.** It is not a rare edge case.

Two ways forward:

- **(a) Lift protection for the operation.** Repo → Settings → Branches → the `main` rule → tick *"Allow force pushes"* (bottom section, *Rules applied to everyone including administrators*). Run the push. **Re-enable immediately after** — the protection is what saved this repo once already.

  **Also untick *"Require status checks to pass before merging"*.** That rule blocks direct pushes to `main`, not merges only, and the rewritten `main` is a commit that has never run CI. `enforce_admins` is `false` here so an admin *may* slip past it, but "may" is the wrong word for a one-shot operation whose failure mode is a partial push. Two boxes out, two boxes back.

  Record the exact prior state first, because the web UI will not restore it for you:
  ```bash
  gh api repos/hoaxpoet/phosphene/branches/main/protection > ~/phosphene-branch-protection-before.json
  ```
  On 2026-08-03 the restore was done from memory and **silently dropped the required `fast-gate` check** — *"Require status checks"* went back on with an empty check list, which gates nothing. Verify with the same command afterwards and diff it, rather than trusting the checkboxes to look right.
- **(b) Leave protection on and accept `main` is not rewritten.** Pointless: `main` still references every old object, so nothing becomes orphaned and the Support request has nothing to purge.

There is no third option where you get the benefit without touching protection.

---

## 5. Execution

```bash
# 1. Dry run. Reviews only; nothing is pushed. Read the whole output —
#    it prints the before-count, the post-rewrite verification, and the
#    text-record sanity check.
bash Scripts/reclaim-lfs-visual-refs.sh 2>&1 | tee ~/lfs-dryrun.log
```

Confirm in the log, and do not proceed without all four:

- `image files to remove:` is the count you expect;
- `OK: 0 image blobs remain`;
- `OK: CODE_AUDIT_2026-06-13.md still in tree` — the canary that text records survived;
- the remaining-LFS list contains only what §2 said it should.

The rewritten mirror is left in `$TMPDIR/phosphene-lfs-purge`. Inspect it directly before trusting it:

```bash
W=$TMPDIR/phosphene-lfs-purge
git -C "$W" lfs ls-files --all | grep -cE 'VISUAL_REFERENCES|diagnostics'   # expect 0
git -C "$W" cat-file -e HEAD:docs/VISUAL_REFERENCES/README.md && echo "READMEs survived"
du -sh "$W"
```

```bash
# 2. Lift branch protection on main (§4a). Web UI; no CLI equivalent worth trusting.

# 3. Execute. Prompts for the literal word "push".
bash Scripts/reclaim-lfs-visual-refs.sh --execute

# 4. RE-ENABLE branch protection immediately.

# 5. Verify main actually moved — if it did not, you are in the §4 split-brain
#    state and should go to §7 now.
git ls-remote origin refs/heads/main
```

---

## 6. After the push — the part that actually saves money

1. **Everyone re-clones.** Existing checkouts are unrecoverable garbage; `git pull` will not fix them. Delete every worktree and clone fresh.
2. **Re-run the local-setup scripts** in each fresh checkout:
   ```bash
   Scripts/fetch_weights.sh      # weights are a Release asset, not in git
   Scripts/link_fixtures.sh      # fixtures + reference images into worktrees
   ```
3. **Open the GitHub Support request.** This is the step that ends the billing. It is not in repo or account settings — it is a separate portal at **<https://support.github.com/request>**. The path is not guessable, so it is written out here:

   *Remove data from a repository I own or control* → *Remove other data* → product **Repositories** (**not** *Billing and payments* — that desk handles invoices and refunds and cannot run a GC; the billing drop is the consequence, not the ask) → **Remove LFS objects**, which exists as a literal radio option on the final form.

   Give the repository as `hoaxpoet/phosphene`, not a bare name. The form asks **"Are you able to delete and recreate the repository?"** — answer **No**, and it is true rather than tactical: deleting destroys the `ml-weights-v1` Release asset that `Scripts/fetch_weights.sh` pulls on every fresh clone, along with the PR and issue history. Answering Yes routes you to the self-service article.

   > Repository `hoaxpoet/phosphene`. We have rewritten history to remove unused Git-LFS objects. Please garbage-collect unreferenced LFS objects for this repository.
   >
   > To be clear, this is a garbage-collection request for objects already made unreferenced by our own history rewrite — not a request to remove sensitive or leaked data, and not a request to delete or recreate the repository.

   That second paragraph matters: without it the ticket reads as a secret-leak report and comes back as an article about rotating credentials. Storage does not drop until they action it.
4. **Confirm the drop** in Settings → Billing → Git LFS Data before calling it done.

---

## 7. Recovery, if the push half-applies

This is a *restore*, not a merge. You are setting each ref back to the SHA it had before.

1. **Do not panic-push anything else.** Every extra force-push makes the state harder to reason about.
2. **Confirm the damage is bounded.** If `main` was rejected it is intact, and the canonical history is fine:
   ```bash
   git ls-remote origin refs/heads/main
   ```
3. **Confirm the old commits are recoverable** — this is the whole ballgame. From a clone that has them:
   ```bash
   awk '{print $1}' ~/phosphene-refs-before-*.txt | while read s; do
     git cat-file -e "$s^{commit}" 2>/dev/null || echo "MISSING $s"
   done
   ```
   Anything reported MISSING is gone once GitHub GCs it. If the pre-flight §3.4 capture was skipped, the force-push output itself lists every `old...new` pair — the left-hand side is what you need.
4. **Restore in one push**, building the refspec from the captured file:
   ```bash
   REFS=$(awk '{printf "+%s:%s ", $1, $2}' ~/phosphene-refs-before-*.txt)
   git push origin $REFS
   ```
5. **Verify every ref**, not just a sample:
   ```bash
   while read -r sha ref; do
     actual=$(git ls-remote origin "$ref" | cut -c1-8)
     [ "$actual" = "${sha:0:8}" ] || echo "MISMATCH $ref: want ${sha:0:8} got $actual"
   done < ~/phosphene-refs-before-*.txt
   ```
6. **Verify coherence, not just SHAs.** Matching SHAs can still leave a broken graph. The real check is that branches share ancestry with `main` again:
   ```bash
   git fetch origin --prune
   git rev-list --count origin/main..origin/claude/<some-branch>
   ```
   A sane number (single or double digits) means recovered. Four digits means still disjoint.

---

## 8. Incident record — 2026-07-31

`--execute` was run with branch protection active. Outcome:

- `main` **rejected** — intact at `517b0d9f`.
- 27 `refs/pull/*` **rejected** — all PRs preserved.
- **18 branches + 3 tags force-updated** to disjoint history.

Recovered fully: all 21 refs restored, 21/21 verified, branch ancestry back to 2–14 commits ahead of `main` (from 1,945–2,099 disjoint). Release assets unaffected throughout — `ml-weights-v1` served its 162 MB asset for the entire incident, so the build was never at risk.

**Recovery worked because the pre-rewrite commits were still in a local object store.** That was luck, not design — no ref capture had been taken beforehand. §3.4 exists so the next attempt does not rely on it.

**Two lessons in the ordering of this document:**

- The dry run reported "94 % smaller, verified clean" and read as a green light. It is not one. The dry run says the *rewrite* is correct; it says nothing about whether the *push* will apply cleanly. §4 is the missing half.
- The half-applied state was strictly worse than either end state: the bill was unchanged **and** the branches were broken. If you cannot complete §4 and §6, do not start §5.

---

## 9. Completion record — 2026-08-03

Ran clean. `main` moved, every ref applied, ancestry coherent.

**Scope:** images **and** weights in one rewrite (§2 decision), 755 of 767 LFS objects.

| | Before | After |
|---|---|---|
| Repo `.git` | 1.4 GB | 82 MB |
| Image objects (`docs/`) | 287 | 0 |
| Weight objects (`ML/Weights/*.bin`) | 468 | 0 |
| Live objects retained | — | 12 (11 `.mlpackage` blobs + `quality_reel.mp4`) |

**The push.** 22 branches + 3 tags force-updated; `main` `2f566e4e` → `57f1e888`. The 28 `refs/pull/*` were rejected as always, so the non-zero exit is expected and is *not* the §4 failure — read the `main` line, not the exit code.

**Verification, in the order that matters.** All 25 heads and tags on origin matched the rewritten mirror exactly. Then ancestry: every branch 1–44 commits ahead of the new `main`, no four-digit numbers. Ancestry is the real check — matching SHAs can still sit on a broken graph.

**What §3 and §4 caught that §8 did not:** both blocking PRs landed or closed first; the `ricercar-echo-look-prompt-bd7993` work was pushed rather than gambled; the ref capture was taken *and* every SHA in it verified present locally, so the undo was real rather than the lucky object-store survival of 2026-07-31.

**Three things this run learned the hard way:**

- The §3.1 local-only check misses a branch with a **dangling upstream**. See §3.1 — this nearly destroyed the same 4 ft3 commits for the second time in three days, and they were rescued as patches with minutes to spare.
- **Required status checks block direct pushes**, not just merges, and the restore afterwards silently dropped `fast-gate`. See §4.
- A **time-based doc gate** can fail CI on a tree nobody touched: `Scripts/rotate_docs.sh` reads local time while CI reads UTC, so on a boundary day it reports "nothing to move" while `fast-gate` fails. `PHOSPHENE_TODAY=YYYY-MM-DD` forces it. Budget for an unrelated CI failure mid-operation.

**Not reclaimed, deliberately:** a 67.9 MB `StemSeparator.mlpackage/.../weight.bin` from the abandoned CoreML dependency still sits in history under `ML/Models/`. It was never an LFS object, so it costs clone size but nothing on the LFS bill. Removing it would mean a second rewrite, and §2 exists to say: not worth the disruption.

**Still open at time of writing:** the Support request was submitted 2026-08-03. **The storage number had not yet dropped.** Until it does, this operation has cost a full disruption and saved nothing — that is §1's point, and it stays true right up until Support actions the GC.
