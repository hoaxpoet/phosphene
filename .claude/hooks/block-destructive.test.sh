#!/usr/bin/env bash
#
# Regression guard for block-destructive.sh. Run after editing that file:
#   bash .claude/hooks/block-destructive.test.sh .claude/hooks/block-destructive.sh
# Exit 0 = all assertions hold. The ALLOW cases matter as much as the BLOCK
# ones: a hook that trips on routine commands gets disabled, which is worse
# than a gap. Added 2026-08-03 with the plumbing-form rules.
# Exercise block-destructive.sh: every BLOCK must exit 2, every ALLOW must exit 0.
# False positives are as bad as misses — a hook that blocks routine commands
# gets disabled, which is worse than one gap.
HOOK="$1"
pass=0; fail=0

check() {  # check <expect: block|allow> <command>
    local expect="$1" cmd="$2" rc
    set +e
    printf '%s' "{\"tool_input\":{\"command\":$(printf '%s' "$cmd" | jq -Rs .)}}" \
        | bash "$HOOK" >/dev/null 2>&1
    rc=$?
    set -e
    if { [ "$expect" = block ] && [ "$rc" -eq 2 ]; } || { [ "$expect" = allow ] && [ "$rc" -eq 0 ]; }; then
        pass=$((pass+1))
    else
        fail=$((fail+1)); echo "  FAIL [want $expect, rc=$rc]: $cmd"
    fi
}

echo "== new plumbing rules: must BLOCK =="
check block 'git update-ref -d refs/heads/foo'
check block 'git update-ref --delete refs/heads/foo'
check block 'git push origin --delete claude/foo'
check block 'git push origin :refs/heads/foo'
check block 'git push origin :foo'
check block 'git reflog expire --expire=now --all'
check block 'git gc --prune=now'
check block 'git gc --aggressive --prune=all'
check block 'git stash drop'
check block 'git stash clear'
check block 'git worktree remove --force .claude/worktrees/x'
check block 'git worktree remove -f .claude/worktrees/x'
check block 'git checkout -f'
check block 'git switch --discard-changes main'
check block 'cd /tmp && git update-ref -d refs/heads/foo'

echo "== pre-existing rules still BLOCK =="
check block 'git reset --hard origin/main'
check block 'git push --force origin main'
check block 'git branch -D claude/foo'
check block 'git clean -fd'
check block 'git checkout .'
check block 'rm -rf /Users/someone/Documents/important'

echo "== must ALLOW (false-positive guards) =="
check allow 'git update-ref refs/heads/foo abc1234'      # restore path stays open
check allow 'git push origin main'
check allow 'git push -u origin claude/my-branch'
check allow 'git push origin local:remote'               # colon refspec, not a delete
check allow 'git gc'
check allow 'git gc --auto'
check allow 'git reflog'
check allow 'git stash list'
check allow 'git stash push -m wip'
check allow 'git worktree remove .claude/worktrees/x'    # unforced: git itself guards
check allow 'git worktree list'
check allow 'git checkout main'
check allow 'git checkout -b feature'
check allow 'git switch main'
check allow 'git branch -d claude/foo'                   # safe lowercase delete
check allow 'git status --short'
check allow 'git log --oneline -5'
check allow 'rm -rf /tmp/scratch'
check allow 'rm -rf .build'
check allow 'echo "do not run git push --delete here"'   # quoted mention

echo "== escape hatch: ALLOW_DESTRUCTIVE=1 must ALLOW =="
check allow 'ALLOW_DESTRUCTIVE=1 git push origin --delete claude/foo'
check allow 'ALLOW_DESTRUCTIVE=1 git branch -D claude/foo'
check allow 'ALLOW_DESTRUCTIVE=1 git reset --hard origin/main'
check allow 'ALLOW_DESTRUCTIVE=1 rm -rf /Users/someone/thing'
check allow 'cd /tmp && ALLOW_DESTRUCTIVE=1 git branch -D foo'    # after && boundary
check allow 'git status; ALLOW_DESTRUCTIVE=1 git stash drop'      # after ; boundary

echo "== escape hatch must NOT be armable by a mention =="
# These matter more than the ALLOW cases above: if any of them passes, the hook
# can be disarmed by text that merely names the marker.
check block 'echo "ALLOW_DESTRUCTIVE=1" && git branch -D claude/foo'    # double-quoted -> stripped
check block "echo 'ALLOW_DESTRUCTIVE=1' && git push origin --delete x"  # single-quoted -> stripped
check block 'git commit -m ALLOW_DESTRUCTIVE=1-note && git branch -D x' # not a bare token
check block 'ALLOW_DESTRUCTIVE=0 git branch -D claude/foo'              # wrong value
check block 'MY_ALLOW_DESTRUCTIVE=1 git branch -D claude/foo'           # not at a boundary
check block 'git log --grep ALLOW_DESTRUCTIVE=1 && git clean -fd'       # mid-command mention

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
