#!/usr/bin/env bash
# Shuts down every booted simulator on the Mac to free its memory. On Linux, this runs on
# the Mac after any queued Skyfold job finishes.
#
#   Tools/stop-sim.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/skyfold.sh"

case "$(uname -s)" in
    Darwin)
        xcrun simctl shutdown all
        printf 'Shut down all simulators.\n'
        ;;
    Linux)
        run_on_mac Tools/stop-sim.sh
        ;;
    *)
        fail "Run this script on Linux or macOS."
        ;;
esac
