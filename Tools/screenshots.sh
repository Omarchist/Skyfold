#!/bin/zsh
# Builds Skyfold for the iOS Simulator, launches it with debug switches, and saves a
# timed series of screenshots.
#
#   Tools/screenshots.sh <name> <portrait|landscape> <count> <interval-seconds> [launch args...]
#
# Examples:
#   Tools/screenshots.sh menu-day portrait 2 4 -SkyfoldTimeOfDay day
#   Tools/screenshots.sh flight landscape 20 3 -SkyfoldAutostart YES -SkyfoldAutopilot YES \
#       -SkyfoldShortLegs YES -SkyfoldAutoGates YES
#
# Environment:
#   SKYFOLD_SIM   simulator UDID (default: iPhone 18 Pro on the newest runtime)
#   SKYFOLD_OUT   output folder (default: <project>/Screenshots)
#   SKYFOLD_WARM  seconds to wait after launch before the first shot (default 6)
set -euo pipefail
ROOT="${0:A:h:h}"
NAME="${1:?name}"; ORIENT="${2:?portrait|landscape}"; COUNT="${3:?count}"; EVERY="${4:?interval}"
shift 4
SIM="${SKYFOLD_SIM:-$(xcrun simctl list devices available | grep 'iPhone 18 Pro (' | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}"
OUT="${SKYFOLD_OUT:-$ROOT/Screenshots}"
WARM="${SKYFOLD_WARM:-6}"
DD="$ROOT/build/DerivedData-$ORIENT"
mkdir -p "$OUT"

overrides=()
if [[ "$ORIENT" == landscape ]]; then
  # Launch straight into landscape: simctl cannot rotate a device, but an app that only
  # supports landscape starts that way.
  overrides+=("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone=UIInterfaceOrientationLandscapeRight")
fi

echo "Building ($ORIENT)…"
xcodebuild -project "$ROOT/Skyfold.xcodeproj" -scheme Skyfold -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" \
  "${overrides[@]}" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$DD/Build/Products/Debug-iphonesimulator/Skyfold.app"
[[ -d "$APP" ]] || { echo "Build failed: no app at $APP"; exit 1; }

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM" com.henry.skyfold 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.henry.skyfold "$@" >/dev/null
/bin/sleep "$WARM"

for i in $(seq -w 1 "$COUNT"); do
  f="$OUT/$NAME-$i.png"
  xcrun simctl io "$SIM" screenshot "$f" >/dev/null 2>&1
  if [[ "$ORIENT" == landscape ]]; then
    # The framebuffer is always portrait; turn the image the right way up.
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
    if (( h > w )); then sips -r 270 "$f" >/dev/null; fi
  fi
  echo "$f"
  /bin/sleep "$EVERY"
done
