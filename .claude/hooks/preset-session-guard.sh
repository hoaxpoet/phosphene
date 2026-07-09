#!/usr/bin/env bash
# preset-session-guard.sh — REVIEW.4 session hooks (the two REVIEW.1 countermeasures).
#
# Modes (one registration per mode in .claude/settings.json):
#   read-track  PostToolUse/Read        — record that a VISUAL_REFERENCES README was read
#   metal-edit  PreToolUse/Edit|Write   — warn ONCE if a .metal edit starts before any README read
#   bash-post   PostToolUse/Bash        — record rendered-evidence runs (RENDER_VISUAL etc.)
#   bash-pre    PreToolUse/Bash         — warn ONCE at `git commit` if shaders edited w/o rendered evidence
#
# Both warnings are NON-BLOCKING nudges (REVIEW.1 measured the prose rules at 35 % compliance;
# these put the rule at the decision point instead). State is per-session under /tmp.
set -u
MODE="${1:-}"
IN=$(cat)
SID=$(printf '%s' "$IN" | jq -r '.session_id // "nosession"')
DIR="/tmp/phosphene_hooks/${SID}"
mkdir -p "$DIR" 2>/dev/null || exit 0

case "$MODE" in
  read-track)
    FP=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // ""')
    case "$FP" in
      *VISUAL_REFERENCES*README*) touch "$DIR/readme_read" ;;
    esac
    ;;

  metal-edit)
    FP=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // ""')
    case "$FP" in
      *.metal)
        touch "$DIR/metal_edited"
        if [ ! -f "$DIR/readme_read" ] && [ ! -f "$DIR/warned_readme" ]; then
          touch "$DIR/warned_readme"
          jq -n '{
            systemMessage: "⚠ .metal edit before the preset-session skill / a VISUAL_REFERENCES README this session (preset-session skill; PRESET_SESSION_CHECKLIST.md item 1).",
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              additionalContext: "Hook notice: no docs/VISUAL_REFERENCES/<preset>/README.md has been Read this session. If this is preset-facing work, invoke the preset-session skill (.claude/skills/preset-session/ — the mandatory opener) and run docs/PRESET_SESSION_CHECKLIST.md before continuing. If this is engine/infra work that touches .metal incidentally, proceed. (This nudge keys off the observable README-read proxy; the harness does not expose Skill-tool invocation to this hook, so skill-load itself is not checked here.)"
            }
          }'
        fi
        ;;
    esac
    ;;

  bash-post)
    CMD=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""')
    case "$CMD" in
      *RENDER_VISUAL=1*|*SKEIN_VISUAL=1*|*PresetSessionReplay*|*replay_report*) touch "$DIR/rendered" ;;
    esac
    ;;

  bash-pre)
    CMD=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""')
    case "$CMD" in
      *"git commit"*)
        if [ -f "$DIR/metal_edited" ] && [ ! -f "$DIR/rendered" ] && [ ! -f "$DIR/warned_render" ]; then
          touch "$DIR/warned_render"
          jq -n '{
            systemMessage: "⚠ Committing after .metal edits with no rendered evidence this session (render-early — PRESET_SESSION_CHECKLIST.md item 6).",
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              additionalContext: "Hook notice: .metal files were edited this session but no RENDER_VISUAL/SKEIN_VISUAL/PresetSessionReplay run has happened. If this commit contains shader tuning, produce a contact sheet first (checklist item 6 — rendered evidence early is what ends tuning spirals). Proceeding is allowed."
            }
          }'
        fi
        ;;
    esac
    ;;
esac
exit 0
