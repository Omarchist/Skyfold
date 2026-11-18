#!/usr/bin/env bash
# Builds Skyfold, opens a simulator window on the Mac, and launches the app with any debug
# switches. On Linux, the build and simulator run on the Mac.
#
#   Tools/run-sim.sh [launch args...]
#   Tools/run-sim.sh -SkyfoldAutostart YES -SkyfoldAutopilot YES
#
# Xcode 27 shows the running simulator in DeviceHub; older Xcode uses Simulator.app.
#
# Environment:
#   SKYFOLD_SIM   simulator UDID (default: a booted iPhone, else the newest iPhone 18 Pro)
#   SKYFOLD_MAC   user@mac-host to use from Linux (default: git config skyfold.mac)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/skyfold.sh"

case "$(uname -s)" in
    Darwin)
        build_app
        boot_simulator
        simulator_app="$(xcode-select -p)/Applications/Simulator.app"
        if [[ -d $simulator_app ]]; then
            open "$simulator_app" --args -CurrentDeviceUDID "$sim"
        else
            # Xcode 27 shows simulators in DeviceHub instead of Simulator.app.
            open -b com.apple.dt.Devices
        fi || printf 'Could not open a simulator window. The app still runs in the background.\n' >&2
        launch_app "$@"
        printf 'Launched Skyfold on simulator %s\n' "$sim"
        ;;
    Linux)
        run_on_mac Tools/run-sim.sh "$@"
        ;;
    *)
        fail "Run this script on Linux or macOS."
        ;;
esac
