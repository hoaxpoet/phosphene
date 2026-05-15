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

PROJECT_ROOT="/Users/braesidebandit/Documents/Projects/phosphene"

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
