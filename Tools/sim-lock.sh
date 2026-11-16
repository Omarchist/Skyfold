#!/bin/zsh
# Runs a command while holding one of two machine-wide "heavy job" slots.
#
# This Mac has 8 GB of RAM. Several agents running xcodebuild, a booted Simulator or Blender
# at once makes it swap, so every heavy cycle (build + install + launch + screenshot, a
# Blender export batch, a swiftc harness build) goes through this wrapper:
#
#   Tools/sim-lock.sh <command> [args...]
#   Tools/sim-lock.sh zsh -c 'xcodebuild ... && xcrun simctl ... && xcrun simctl io ...'
#
# Keep the wrapped command short (a minute or two). Do not hold a slot while thinking, and
# shut down any Simulator you booted (xcrun simctl shutdown <udid>) when your cycle is done.
# Slots are released automatically if the command exits, fails or is interrupted.
#
# Pools: the default pool ("heavy", 2 slots) is for xcodebuild, Simulators and swiftc
# harness builds. Blender has its own single slot:
#   SKYFOLD_POOL=blender SKYFOLD_SLOTS=1 Tools/sim-lock.sh /Applications/Blender.app/Contents/MacOS/Blender …
set -u
POOL="${SKYFOLD_POOL:-heavy}"
SLOTS="${SKYFOLD_SLOTS:-2}"
BASE="${TMPDIR:-/tmp}/skyfold-$POOL-slots"
mkdir -p "$BASE"
MY=""
booted() { xcrun simctl list devices booted 2>/dev/null | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | sort; }
BEFORE=""
cleanup() {
  # Shut down any Simulator this job booted, so finished jobs never leave one running
  # (three idle Simulators on this 8 GB Mac pushed it deep into swap).
  if [[ -n "$MY" && "$POOL" == heavy ]]; then
    for u in $(comm -13 <(print -r -- "$BEFORE") <(booted)); do xcrun simctl shutdown "$u" 2>/dev/null; done
  fi
  [[ -n "$MY" ]] && rmdir "$MY" 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

waited=0
while [[ -z "$MY" ]]; do
  for i in $(seq 1 $SLOTS); do
    d="$BASE/slot$i"
    # A slot directory older than 25 minutes belongs to a dead job; reclaim it.
    if [[ -d "$d" ]] && [[ -n "$(find "$d" -maxdepth 0 -mmin +25 2>/dev/null)" ]]; then rmdir "$d" 2>/dev/null; fi
    if mkdir "$d" 2>/dev/null; then MY="$d"; break; fi
  done
  if [[ -z "$MY" ]]; then
    (( waited % 60 == 0 )) && echo "sim-lock: waiting for a free slot (${waited}s)…" >&2
    /bin/sleep 5; waited=$((waited + 5))
  fi
done
echo "sim-lock: got ${MY:t} after ${waited}s" >&2
[[ "$POOL" == heavy ]] && BEFORE="$(booted)"
"$@"
