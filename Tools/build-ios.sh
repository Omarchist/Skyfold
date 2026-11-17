#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

case "$(uname -s)" in
    Darwin)
        [[ $# == 0 ]] || fail "Usage on macOS: Tools/build-ios.sh"
        if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null; then
            fail "Select Xcode 27 or later with iOS platform support and complete its first-launch setup."
        fi

        derived_data="${SKYFOLD_DERIVED_DATA:-$root/build/DerivedData-headless}"
        mkdir -p "$derived_data"
        derived_data=$(cd "$derived_data" && pwd -P)
        xcodebuild -project Skyfold.xcodeproj -scheme Skyfold -configuration Debug \
            -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" \
            -jobs 2 -quiet "ARCHS=$(uname -m)" CODE_SIGNING_ALLOWED=NO \
            COMPILER_INDEX_STORE_ENABLE=NO build

        app="$derived_data/Build/Products/Debug-iphonesimulator/Skyfold.app"
        [[ -d "$app" ]] || fail "Xcode did not produce an app at $app"
        printf 'Built %s\n' "$app"
        ;;
    Linux)
        [[ $# -le 1 ]] || fail "Usage on Linux: Tools/build-ios.sh [user@mac-host]"
        mac_host=${1:-${SKYFOLD_MAC:-}}
        if [[ -z "$mac_host" ]]; then
            mac_host=$(git config --local --get skyfold.mac || true)
        fi
        [[ "$mac_host" =~ ^([[:alnum:]_][[:alnum:]_.-]*@)?[[:alnum:]_][[:alnum:]_.-]*$ ]] ||
            fail "Set skyfold.mac in your local Git config, set SKYFOLD_MAC, or pass user@mac-host."
        for command in ssh rsync flock; do
            command -v "$command" >/dev/null || fail "Install $command to run remote Xcode builds."
        done

        # Queue builds to this Mac across worktrees on this Linux machine.
        cache="${XDG_CACHE_HOME:-$HOME/.cache}/skyfold"
        mkdir -p "$cache"
        exec 9>"$cache/$mac_host.lock"
        flock 9

        # Each checkout gets its own source mirror and incremental Xcode build cache.
        checkout_id=$(printf '%s\n' "$(hostname)" "$root" | sha256sum)
        remote_dir=".cache/skyfold-builds/${checkout_id%% *}"
        ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)
        ssh "${ssh_options[@]}" "$mac_host" "mkdir -p '$remote_dir/source'"
        rsync -rltcR --delete --exclude='.DS_Store' --exclude='xcuserdata/' --exclude='*.xcuserstate' \
            -e "ssh ${ssh_options[*]}" \
            Skyfold Skyfold.xcodeproj Tools/build-ios.sh "$mac_host:$remote_dir/source/"
        ssh "${ssh_options[@]}" "$mac_host" \
            "cd '$remote_dir/source' && env SKYFOLD_DERIVED_DATA=../DerivedData /bin/bash Tools/build-ios.sh"
        ;;
    *)
        fail "Run this script on Linux or macOS."
        ;;
esac
