#!/usr/bin/env bash
# Builds the unsigned Debug simulator app with Xcode. On Linux, the build runs on the Mac.
#
#   Tools/build-ios.sh [user@mac-host]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/skyfold.sh"

case "$(uname -s)" in
    Darwin)
        [[ $# == 0 ]] || fail "Usage on macOS: Tools/build-ios.sh"
        build_app
        printf 'Built %s\n' "$app"
        ;;
    Linux)
        [[ $# -le 1 ]] || fail "Usage on Linux: Tools/build-ios.sh [user@mac-host]"
        [[ $# == 0 ]] || SKYFOLD_MAC=$1
        run_on_mac Tools/build-ios.sh
        ;;
    *)
        fail "Run this script on Linux or macOS."
        ;;
esac
