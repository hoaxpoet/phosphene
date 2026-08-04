#!/usr/bin/env bash
# block-destructive.sh — PreToolUse Bash hook.
#
# Reads Claude Code's hook JSON from stdin, extracts the proposed bash command,
# and exits 2 (with a stderr message) when the command matches a denied
# pattern. Exit 2 from a PreToolUse hook tells the harness to deny the tool
# call and surface the stderr back to the agent — the agent can then ask the
# user for explicit approval before re-issuing.
#
# Denied:
#   git reset --hard
#   git push --force / -f / --force-with-lease
#   git branch -D / --delete --force
#   git clean -f / -fd / -ff / --force
#   git checkout .          (wide-form discard)
#   git restore .           (same shape)
#   rm -rf <absolute path>  outside the build-cache allowlist
#
# Denied — plumbing / low-level equivalents (added 2026-08-03):
#   git update-ref -d               deletes a ref directly; the exact bypass for `branch -D`
#   git push --delete / :refspec    deletes a REMOTE branch (was entirely unguarded)
#   git reflog expire --expire=now  destroys the recovery net the rules above rely on
#   git gc --prune=now / --prune=all        same
#   git stash drop / clear          discards stashed work, with no reflog path back
#   git worktree remove --force     discards uncommitted work inside a worktree
#   git checkout -f / switch --discard-changes   flag-form of the blocked `checkout .`
#
# Why these were added: on 2026-08-03 `git branch -D` was refused here, and the
# same deletion then went through as `git update-ref -d refs/heads/<branch>` —
# approved by the user, but it showed the guard only covered the porcelain
# spelling. The same audit deleted eight remote branches via `git push --delete`
# without the hook seeing any of them. The rule of thumb when extending this
# file: block by EFFECT, not by command name. If a new incantation destroys
# commits, refs, or uncommitted work, it belongs here regardless of which
# porcelain/plumbing layer it lives in.
#
# The reflog entries are load-bearing, not merely tidy: two of the reasons below
# say "recoverable only via reflog", so anything that expires or prunes the
# reflog silently downgrades every other rule in this file from recoverable to
# permanent. That is why `reflog expire` and `gc --prune` are here despite being
# maintenance commands rather than obviously destructive ones.
#
# rm -rf allowlist (absolute paths only):
#   /tmp[...]
#   <project>/.build[...]
#   <project>/PhospheneEngine/.build[...]
#   <project>/PhospheneTools/.build[...]
#   <project>/DerivedData[...]
# Relative-path rm -rf (rm -rf .build) is NOT blocked — limited blast radius
# and routinely needed for build-cache wipes.
#
# Best-effort: a determined agent can sidestep via `bash -c "..."` or `eval`.
# This hook catches the common-case accidental destructive call, not malice.
#
# Known limitations:
#   - HEREDOC bodies (`<<EOF ... EOF`) are NOT stripped, so a commit message
#     written via heredoc that mentions a denied pattern in plain text will
#     trip the hook. Workaround: rephrase the heredoc body, or quote-wrap the
#     literal (e.g. `the "git reset --hard" command`).
#   - `bash -c "git reset --hard"` is detected only by the outer `bash -c`
#     argument string, which IS quoted and gets stripped — the inner command
#     slips through. Treat this as a deliberate override path, not a bug.

set -euo pipefail

# Derived, not hardcoded — the hook must resolve on any contributor's checkout
# (hooks run with cwd = the project dir; inside a worktree rev-parse still
# yields that worktree's root, which is the right .build to allowlist).
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# Strip single- and double-quoted substrings from the command before matching.
# This reduces false positives from commands like `echo 'rm -rf /tmp'` or
# `grep "git reset --hard" docs/`. Best-effort: backslash-escaped quotes inside
# quotes are not handled, but those are rare in agent-generated commands.
scan="$cmd"
scan="$(printf '%s' "$scan" | sed -E "s/'[^']*'//g")"
scan="$(printf '%s' "$scan" | sed -E 's/"[^"]*"//g')"

block() {
    {
        echo "[block-destructive] Refused to run: $cmd"
        echo "[block-destructive] Matched pattern: $1"
        echo "[block-destructive] Reason: $2"
        echo "[block-destructive] If this is intentional, ask the user for explicit approval."
        echo "[block-destructive] To override permanently, edit .claude/hooks/block-destructive.sh."
    } >&2
    exit 2
}

# --- git patterns -----------------------------------------------------------

# git reset --hard
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?reset[[:space:]]+([^|;&]*[[:space:]])?--hard\b'; then
    block 'git reset --hard' 'rewrites branch tip; lost commits recoverable only via reflog'
fi

# git push --force / -f / --force-with-lease
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?push\b([^|;&]*)(--force\b|--force-with-lease\b|[[:space:]]-f([[:space:]]|$))'; then
    block 'git push --force' 'rewrites remote history'
fi

# git branch -D / --delete --force
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?branch\b([^|;&]*)(--delete[[:space:]]+--force\b|[[:space:]]-D([[:space:]]|$))'; then
    block 'git branch -D' 'force-deletes unmerged branches'
fi

# git clean with any -f
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?clean\b([^|;&]*)([[:space:]]-[a-zA-Z]*f[a-zA-Z]*|--force)'; then
    block 'git clean -f' 'deletes untracked files (may include in-progress work)'
fi

# git checkout .
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?checkout[[:space:]]+\.([[:space:]]|$|;|\||&)'; then
    block 'git checkout .' 'discards every uncommitted change in the worktree'
fi

# git restore .
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?restore\b([^|;&]*)[[:space:]]\.([[:space:]]|$|;|\||&)'; then
    block 'git restore .' 'discards every uncommitted change in the worktree'
fi

# --- git plumbing / low-level equivalents -----------------------------------
# Same effects as the porcelain rules above, different spellings. See the header
# note: block by effect, not by command name.

# git update-ref -d / --delete  — the direct bypass for `git branch -D`.
# Only the delete form is blocked; `update-ref <ref> <sha>` is left alone since
# it is how a ref gets RESTORED, which is the remedy we want to stay available.
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?update-ref\b([^|;&]*)(--delete\b|[[:space:]]-d([[:space:]]|$))'; then
    block 'git update-ref -d' 'deletes a ref directly — same effect as git branch -D'
fi

# git push --delete <branch>  /  git push origin :branch
# Deletes a REMOTE branch. The colon form matches only a refspec that STARTS
# with ':' (the delete shape) — `git push origin local:remote` is untouched.
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?push\b([^|;&]*)(--delete\b|[[:space:]]-d([[:space:]]|$)|[[:space:]]:[^[:space:]|;&]+)'; then
    block 'git push --delete' 'deletes a remote branch; recovery depends on the remote'"'"'s own GC window'
fi

# git reflog expire --expire=now / --expire-unreachable=now
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?reflog[[:space:]]+([^|;&]*[[:space:]])?expire\b'; then
    block 'git reflog expire' 'destroys the reflog — the recovery path every other rule in this hook depends on'
fi

# git gc --prune=now / --prune=all  (plain `git gc` is fine and stays allowed)
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?gc\b([^|;&]*)--prune=(now|all)\b'; then
    block 'git gc --prune=now' 'drops unreachable objects immediately, making reflog-recoverable commits permanently unrecoverable'
fi

# git stash drop / git stash clear
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?stash[[:space:]]+([^|;&]*[[:space:]])?(drop|clear)\b'; then
    block 'git stash drop/clear' 'discards stashed work; stashes are not covered by the branch reflog'
fi

# git worktree remove --force  (plain `worktree remove` already refuses on dirty)
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?worktree[[:space:]]+remove\b([^|;&]*)(--force\b|[[:space:]]-f([[:space:]]|$))'; then
    block 'git worktree remove --force' 'discards uncommitted work inside the worktree — the unforced form refuses for exactly that reason'
fi

# git checkout -f / git switch -f / --discard-changes — flag-form of `checkout .`
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+([^|;&]*[[:space:]])?(checkout|switch)\b([^|;&]*)(--force\b|--discard-changes\b|[[:space:]]-f([[:space:]]|$))'; then
    block 'git checkout -f' 'discards every uncommitted change in the worktree'
fi

# --- rm -rf with absolute paths --------------------------------------------

# Detect rm with both recursive (-r / -R) and force (-f) flags in any ordering.
# The [rR] / [fF] character classes catch both `rm -rf` and `rm -Rf`.
if printf '%s' "$scan" | grep -qE '(^|[^[:alnum:]_/])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF]|-[a-zA-Z]*[fF][a-zA-Z]*[rR]|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)\b'; then
    # Word-split the command (best-effort; doesn't handle quoted paths with spaces).
    # Disable globbing while we tokenize so /foo/* in the command doesn't expand.
    set -f
    read -ra words <<< "$scan"
    set +f
    for word in "${words[@]}"; do
        case "$word" in
            /*)
                case "$word" in
                    /tmp|/tmp/*) ;;
                    "$PROJECT_ROOT/.build"|"$PROJECT_ROOT/.build/"*) ;;
                    "$PROJECT_ROOT/PhospheneEngine/.build"|"$PROJECT_ROOT/PhospheneEngine/.build/"*) ;;
                    "$PROJECT_ROOT/PhospheneTools/.build"|"$PROJECT_ROOT/PhospheneTools/.build/"*) ;;
                    "$PROJECT_ROOT/DerivedData"|"$PROJECT_ROOT/DerivedData/"*) ;;
                    *)
                        block "rm -rf $word" 'absolute path outside build-cache allowlist'
                        ;;
                esac
                ;;
        esac
    done
fi

exit 0
