#!/bin/zsh
# Typechecks Skyfold/Core plus whatever extra Swift files or folders you pass,
# using the same language settings as the Xcode target. Lets several people
# (or agents) verify their own module without needing every other folder to
# compile yet.
#
#   Tools/typecheck.sh Skyfold/Audio
#   Tools/typecheck.sh Skyfold/UI /path/to/Stubs.swift
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

files=()
files+=(${(f)"$(find Skyfold/Core -name '*.swift')"})
for arg in "$@"; do
  if [[ -d "$arg" ]]; then
    files+=(${(f)"$(find "$arg" -name '*.swift')"})
  else
    files+=("$arg")
  fi
done

xcrun -sdk iphonesimulator swiftc -typecheck \
  -target arm64-apple-ios18.0-simulator -sdk "$SDK" \
  -module-name Skyfold -parse-as-library \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  "${files[@]}"
echo "typecheck OK (${#files[@]} files)"
