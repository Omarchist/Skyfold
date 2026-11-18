# Shared helpers for the Skyfold scripts in Tools/. Source this file and do not run it.
# The code must run in bash 3.2 on macOS and in current bash on Linux.

skyfold_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
bundle_id=com.henry.skyfold

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Runs Tools/<script> on the configured Mac against a mirror of this checkout, then copies
# any screenshots back into Screenshots/. Jobs from this Linux machine to one Mac run one at
# a time, because the Mac has little memory.
run_on_mac() {
    local host=${SKYFOLD_MAC:-}
    if [[ -z $host ]]; then
        host=$(git -C "$skyfold_root" config --get skyfold.mac || true)
    fi
    [[ $host =~ ^([[:alnum:]_][[:alnum:]_.-]*@)?[[:alnum:]_][[:alnum:]_.-]*$ ]] ||
        fail "Set skyfold.mac in your local Git config, set SKYFOLD_MAC, or pass user@mac-host."
    local command
    for command in ssh rsync flock; do
        command -v "$command" >/dev/null || fail "Install $command to run Xcode and Simulator jobs on the Mac."
    done

    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/skyfold"
    mkdir -p "$cache"
    exec 9>"$cache/$host.lock"
    if ! flock -n 9; then
        printf 'Waiting for another Skyfold job on %s to finish…\n' "$host" >&2
        flock 9
    fi

    # Each checkout gets its own source mirror and incremental Xcode build cache.
    local checkout_id
    checkout_id=$(printf '%s\n' "$(hostname)" "$skyfold_root" | sha256sum)
    local remote_dir=".cache/skyfold-builds/${checkout_id%% *}"
    local ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)
    ssh "${ssh_options[@]}" "$host" "mkdir -p '$remote_dir/source' && rm -rf '$remote_dir/Screenshots'"
    (
        cd "$skyfold_root"
        rsync -rltcR --delete --exclude='.DS_Store' --exclude='xcuserdata/' --exclude='*.xcuserstate' \
            -e "ssh ${ssh_options[*]}" \
            Skyfold Skyfold.xcodeproj Tools/lib Tools/*.sh "$host:$remote_dir/source/"
    )

    command="cd '$remote_dir/source' && env SKYFOLD_REMOTE=1"
    command+=" SKYFOLD_DERIVED_DATA=../DerivedData SKYFOLD_OUT=../Screenshots"
    local name value
    for name in SKYFOLD_SIM SKYFOLD_WARM; do
        value=${!name:-}
        [[ -z $value ]] || command+=" $name=$(printf '%q' "$value")"
    done
    command+=" /bin/bash"
    command+=$(printf ' %q' "$@")
    local status=0
    ssh "${ssh_options[@]}" "$host" "$command" || status=$?

    local shots
    shots=$(ssh "${ssh_options[@]}" "$host" "cd '$remote_dir/Screenshots' 2>/dev/null && ls" || true)
    if [[ -n $shots ]]; then
        local out=${SKYFOLD_OUT:-$skyfold_root/Screenshots}
        mkdir -p "$out"
        out=$(cd "$out" && pwd -P)
        rsync -rt -e "ssh ${ssh_options[*]}" "$host:$remote_dir/Screenshots/" "$out/"
        local shot
        while IFS= read -r shot; do
            printf '%s\n' "$out/$shot"
        done <<<"$shots"
    fi
    return "$status"
}

# Builds the unsigned Debug simulator app and sets app to its path. Pass "landscape" to build
# a landscape-only variant, which launches in landscape because simctl cannot rotate a device.
build_app() {
    xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1 ||
        fail "Select Xcode 27 or later with iOS platform support and complete its first-launch setup."
    local derived_data="${SKYFOLD_DERIVED_DATA:-$skyfold_root/build/DerivedData-headless}"
    local settings=("ARCHS=$(uname -m)" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO)
    if [[ ${1:-} == landscape ]]; then
        derived_data+=-landscape
        settings+=(INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone=UIInterfaceOrientationLandscapeRight)
    fi
    mkdir -p "$derived_data"
    derived_data=$(cd "$derived_data" && pwd -P)
    xcodebuild -project "$skyfold_root/Skyfold.xcodeproj" -scheme Skyfold -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" \
        -jobs 2 -quiet "${settings[@]}" build
    app="$derived_data/Build/Products/Debug-iphonesimulator/Skyfold.app"
    [[ -d $app ]] || fail "Xcode did not produce an app at $app"
}

# Sets sim to SKYFOLD_SIM, a booted iPhone, the newest iPhone 18 Pro, or any iPhone, in that
# order. Boots it if needed and sets booted_here to yes when this call booted it.
boot_simulator() {
    local udid='s/.*\(([0-9A-F-]{36})\).*/\1/'
    sim=${SKYFOLD_SIM:-}
    if [[ -z $sim ]]; then
        local devices
        devices=$(xcrun simctl list devices available)
        sim=$(grep -E '^ +iPhone .*\(Booted\)' <<<"$devices" | head -1 | sed -E "$udid" || true)
        [[ -n $sim ]] || sim=$(grep -E '^ +iPhone 18 Pro \(' <<<"$devices" | tail -1 | sed -E "$udid" || true)
        [[ -n $sim ]] || sim=$(grep -E '^ +iPhone ' <<<"$devices" | tail -1 | sed -E "$udid" || true)
        [[ -n $sim ]] || fail "Create an iPhone simulator in Xcode, or set SKYFOLD_SIM to a simulator UDID."
    fi
    booted_here=no
    if ! xcrun simctl list devices booted | grep -q "$sim"; then
        printf 'Booting simulator %s…\n' "$sim" >&2
        booted_here=yes
    fi
    xcrun simctl bootstatus "$sim" -b >/dev/null
}

# Installs app on sim and relaunches Skyfold with any launch arguments.
launch_app() {
    xcrun simctl terminate "$sim" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl install "$sim" "$app"
    xcrun simctl launch "$sim" "$bundle_id" "$@" >/dev/null
}
