#!/usr/bin/env bash
# capture.sh — take the DS.2 before/after tile captures.
#
#   docs/reviews/DS.2/capture.sh before    # run from a checkout at main
#   docs/reviews/DS.2/capture.sh after     # run from the DS.2 branch
#   python3 docs/reviews/DS.2/make_index.py
#
# REQUIRES AN UNLOCKED SCREEN. At the lock screen every capture returns black
# and the app's view hierarchy is absent from the accessibility tree — that is
# what blocked DS.2's own captures. Also needs Screen Recording + Accessibility
# granted to the process driving this (Claude / claude, NOT Uzume) — see
# env_ui_automation_accessibility_grant.
#
# Window capture by id (-l) and by rect (-R) both fail on Uzume's Metal-backed
# window, so this captures the whole display and crops.
set -euo pipefail

KIND="${1:?usage: capture.sh before|after}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/$KIND"; mkdir -p "$OUT"
REPO="$(cd "$ROOT/../../.." && pwd)"

APP="$(xcodebuild -project "$REPO/UzumeApp.xcodeproj" -scheme UzumeApp \
        -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Uzume.app"
[ -d "$APP" ] || { echo "build first: xcodebuild -scheme UzumeApp -destination 'platform=macOS' build"; exit 1; }

# A window frame persisted against a display that no longer exists launches the
# app fully off-screen; clearing the saved state is what recovers it.
pkill -f "Uzume.app/Contents/MacOS/Uzume" 2>/dev/null || true; sleep 1
rm -rf ~/Library/"Saved Application State"/io.uzume.mac.savedState
"$APP/Contents/MacOS/Uzume" >/dev/null 2>&1 &
sleep 7

shot() {  # shot <name> <x> <y> <w> <h>
  local f="$OUT/$1.png"
  screencapture -x -o -D1 "$f"
  sips -c "$5" "$4" --cropOffset "$3" "$2" "$f" >/dev/null
  echo "  $1.png"
}

cat <<'EOF'
Drive the UI by hand for each shot, then press Return here:
  1 connector_apple_music / _hover / _spotify / _local  — open "Connect a playlist"
  2 connector_apple_music_unavailable                   — quit Music.app first
  3 lf_folder / lf_file / lf_playlist (+ _hover)        — pick "Local files"
Hover = leave the pointer on the tile before pressing Return.
EOF

# Window bounds, re-read each time so a moved window still crops correctly.
bounds() {
  python3 - <<'PY'
import subprocess, re
out = subprocess.run(["osascript","-e",
  'tell application "System Events" to tell process "Uzume" to get {position, size} of window 1'],
  capture_output=True, text=True).stdout
n = [int(x) for x in re.findall(r'-?\d+', out)]
print(*n[:4]) if len(n) >= 4 else print("135 265 810 569")
PY
}

for name in "${@:2}"; do
  read -r -p "position the UI for '$name', then Return… " _
  # shellcheck disable=SC2046
  shot "$name" $(bounds)
done
echo "done → $OUT"
