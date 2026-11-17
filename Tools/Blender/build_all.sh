#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$tools_dir/../.." && pwd)
blender=${BLENDER:-blender}
if [[ -z "${BLENDER:-}" ]] && ! command -v blender >/dev/null 2>&1 &&
   [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    blender=/Applications/Blender.app/Contents/MacOS/Blender
fi
if ! command -v "$blender" >/dev/null 2>&1; then
    printf 'Install Blender 5.2 or set BLENDER to its executable.\n' >&2
    exit 1
fi

staging=$(mktemp -d "${TMPDIR:-/tmp}/skyfold-blender.XXXXXXXX")
trap 'rm -r -- "$staging"' EXIT
mkdir -p -- "$staging/models" "$staging/previews"

run_blender() {
    "$blender" --background --factory-startup --python-exit-code 1 "$@"
}

model_scripts=()
for script in "$tools_dir"/models/*.py; do
    model_scripts+=(--python "$script")
done

run_blender "${model_scripts[@]}" -- --out "$staging/models"
run_blender --python "$tools_dir/verify_usdz.py" -- "$staging/models"
run_blender --python "$tools_dir/render_previews.py" -- \
    --models-dir "$staging/models" --preview-dir "$staging/previews"
run_blender --python "$tools_dir/render_icon.py" -- \
    --day "$staging/AppIcon.png" --night "$staging/previews/icon_night.png"

cp -- "$staging/models/"*.usdz "$root/Skyfold/Resources/Models/"
cp -- "$staging/previews/"*.png "$tools_dir/previews/"
cp -- "$staging/AppIcon.png" "$root/Skyfold/Assets.xcassets/AppIcon.appiconset/"
