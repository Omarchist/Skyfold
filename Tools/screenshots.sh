#!/usr/bin/env bash
# Builds Skyfold for the iOS Simulator, launches it with debug switches, and saves a
# timed series of screenshots. On Linux, the build and Simulator run on the Mac and the
# screenshots are copied back. The script prints the path of each saved screenshot.
#
#   Tools/screenshots.sh <name> <portrait|landscape> <count> <interval-seconds> [launch args...]
#
# Examples:
#   Tools/screenshots.sh menu-day portrait 2 4 -SkyfoldTimeOfDay day
#   Tools/screenshots.sh flight landscape 20 3 -SkyfoldAutostart YES -SkyfoldAutopilot YES \
#       -SkyfoldShortLegs YES -SkyfoldAutoGates YES
#
# Environment:
#   SKYFOLD_SIM       simulator UDID (default: a booted iPhone, else the newest iPhone 18 Pro)
#   SKYFOLD_OUT       output folder (default: <project>/Screenshots)
#   SKYFOLD_WARM      seconds to wait after Skyfold first draws before the first shot
#                     (default 3)
#   SKYFOLD_MAC       user@mac-host to use from Linux (default: git config skyfold.mac)
#
# The simulator stays booted so the next run starts in seconds. Run Tools/stop-sim.sh
# to free the Mac's memory.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/skyfold.sh"

usage="Usage: Tools/screenshots.sh <name> <portrait|landscape> <count> <interval-seconds> [launch args...]"
[[ $# -ge 4 ]] || fail "$usage"
name=$1 orientation=$2 count=$3 interval=$4
shift 4
[[ $name =~ ^[[:alnum:]_.-]+$ ]] || fail "Use only letters, digits, dots, dashes and underscores in the name."
[[ $orientation == portrait || $orientation == landscape ]] || fail "$usage"
[[ $count =~ ^[1-9][0-9]*$ && $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "$usage"

case "$(uname -s)" in
    Darwin) ;;
    Linux)
        run_on_mac Tools/screenshots.sh "$name" "$orientation" "$count" "$interval" "$@"
        exit
        ;;
    *) fail "Run this script on Linux or macOS." ;;
esac

out=${SKYFOLD_OUT:-$skyfold_root/Screenshots}
mkdir -p "$out"
out=$(cd "$out" && pwd -P)

printf 'Building (%s)…\n' "$orientation" >&2
build_app "$orientation"
boot_simulator

# Skyfold can take a minute to draw its first frame after a cold boot, so wait for it by
# PNG size. A blank screen compresses to well under 120 KB. The home screen is larger but
# keeps a steady size, so the app counts as drawn when the size moves more than 10% away.
probe="$out/.probe-$$.png"
trap 'rm -f "$probe"' EXIT
blank=120000
screen_size() {
    if xcrun simctl io "$sim" screenshot "$probe" >/dev/null 2>&1; then
        stat -f %z "$probe"
    else
        printf '0\n'
    fi
}
xcrun simctl terminate "$sim" "$bundle_id" >/dev/null 2>&1 || true
home=0
for ((waited = 0; waited < 60 && home <= blank; waited += 2)); do
    sleep 2
    home=$(screen_size)
done
launch_app "$@"
printf 'Waiting for Skyfold to draw…\n' >&2
for ((waited = 0; waited < 90; waited += 2)); do
    sleep 2
    size=$(screen_size)
    if ((size > blank && (size - home > home / 10 || home - size > home / 10))); then break; fi
done
sleep "${SKYFOLD_WARM:-3}"

for ((i = 1; i <= count; i++)); do
    file=$(printf '%s/%s-%02d.png' "$out" "$name" "$i")
    xcrun simctl io "$sim" screenshot "$file" >/dev/null 2>&1
    if [[ $orientation == landscape ]]; then
        # The framebuffer is always portrait; turn the image the right way up.
        width=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
        height=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')
        if ((height > width)); then sips -r 270 "$file" >/dev/null; fi
    fi
    # From Linux, run_on_mac prints the local copies instead.
    if [[ -z ${SKYFOLD_REMOTE:-} ]]; then
        printf '%s\n' "$file"
    else
        printf 'Saved %s (%d of %d)\n' "${file##*/}" "$i" "$count" >&2
    fi
    if ((i < count)); then sleep "$interval"; fi
done
