#!/bin/bash
# Package a locally built Release iOS Simulator app for Apple Silicon Macs.
set -euo pipefail

usage() {
  echo "Usage: $0 [--allow-dirty] APP_PATH OUTPUT_DIRECTORY" >&2
  exit 2
}

allow_dirty=false
if [[ ${1:-} == --allow-dirty ]]; then
  allow_dirty=true
  shift
fi
[[ $# == 2 ]] || usage
app=$1
output=$2
[[ -d "$app" && $(basename "$app") == Cinue.app ]] || { echo "Expected a Cinue.app bundle" >&2; exit 1; }
[[ -d "$output" ]] || { echo "Output directory must already exist" >&2; exit 1; }
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
commit=$(git -C "$repo" rev-parse HEAD)
status=$(git -C "$repo" status --porcelain --untracked-files=normal)
if [[ -n "$status" ]]; then
  if [[ "$allow_dirty" != true ]]; then
    echo "Source checkout has uncommitted changes; use --allow-dirty for local review only" >&2
    exit 1
  fi
fi
plist="$app/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
executable=$(read_plist CFBundleExecutable)
version=$(read_plist CFBundleShortVersionString)
build=$(read_plist CFBundleVersion)
minimum_os=$(read_plist MinimumOSVersion)
bundle_id=$(read_plist CFBundleIdentifier)
source_revision=$(read_plist CinueSourceRevision) || { echo "Missing build source revision" >&2; exit 1; }
source_modified=$(read_plist CinueSourceModified) || { echo "Missing build source modification status" >&2; exit 1; }
[[ "$source_revision" == "$commit" ]] || { echo "Build source revision does not match checkout HEAD" >&2; exit 1; }
case "$source_modified" in
  false|NO|0) provenance=clean ;;
  true|YES|1) provenance=dirty ;;
  *) echo "Invalid build source modification status" >&2; exit 1 ;;
esac
if [[ "$provenance" == dirty && "$allow_dirty" != true ]]; then
  echo "Build used a modified source checkout; use --allow-dirty for local review only" >&2
  exit 1
fi
if [[ -n "$status" && "$provenance" == clean ]]; then
  echo "Clean build metadata does not match the modified checkout" >&2
  exit 1
fi
sdk=$(read_plist DTSDKName 2>/dev/null || printf 'Unavailable')
toolchain=$(read_plist DTXcode 2>/dev/null || printf 'Unavailable')
[[ -n "$executable" && -n "$version" && -n "$build" && -n "$minimum_os" && -n "$bundle_id" ]] || { echo "Missing bundle metadata" >&2; exit 1; }
binary="$app/$executable"
[[ -f "$binary" ]] || { echo "Bundle executable is missing" >&2; exit 1; }
architectures=$(lipo -archs "$binary")
[[ "$architectures" == arm64 ]] || { echo "Expected arm64 only, found: $architectures" >&2; exit 1; }
platform=$(xcrun vtool -show-build "$binary")
printf '%s\n' "$platform" | grep -Eq 'platform (IOSSIMULATOR|7)([[:space:]]|$)' || { echo "Executable is not an iOS Simulator binary" >&2; exit 1; }
# Reject platform metadata that is absent or disagrees with the bundle.
binary_minimum=$(printf '%s\n' "$platform" | awk '$1 == "minos" {print $2; exit}')
[[ "$binary_minimum" == "$minimum_os" ]] || { echo "Minimum OS version differs between binary and bundle" >&2; exit 1; }

archive="$output/Cinue-iOS-Simulator-arm64.zip"
checksum="$output/Cinue-iOS-Simulator-arm64.zip.sha256"
metadata="$output/Cinue-iOS-Simulator-arm64.txt"
[[ ! -e "$archive" && ! -e "$checksum" && ! -e "$metadata" ]] || { echo "Output files already exist" >&2; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cinue-simulator.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
# ditto preserves bundle resources and executable permissions.
ditto "$app" "$tmp/Cinue.app"
# Nested executable code needs its own signing strategy; fail rather than
# replacing signatures recursively without inspecting the embedded components.
while IFS= read -r -d '' candidate; do
  [[ "$candidate" == "$tmp/Cinue.app/$executable" ]] && continue
  if file -b "$candidate" | grep -q 'Mach-O'; then
    echo "Nested executable code requires explicit signing support: ${candidate#"$tmp/Cinue.app/"}" >&2
    exit 1
  fi
done < <(find "$tmp/Cinue.app" -type f -print0)
strip -S "$tmp/Cinue.app/$executable"
codesign --force --sign - --timestamp=none "$tmp/Cinue.app"
codesign --verify --deep --strict "$tmp/Cinue.app"
ditto -c -k --keepParent "$tmp/Cinue.app" "$tmp/Cinue-iOS-Simulator-arm64.zip"
cat > "$tmp/Cinue-iOS-Simulator-arm64.txt" <<INFO
Cinue iOS Simulator package

Version: $version ($build)
Bundle identifier: $bundle_id
Platform: iOS Simulator
Architecture: arm64 (Apple Silicon)
Declared minimum iOS Simulator version: $minimum_os
Tested Simulator runtime: Not specified
Build SDK: $sdk
Xcode version code: $toolchain
Build source revision: $source_revision
Build source checkout: $provenance

Requires a Mac with Apple Silicon, Xcode, and a compatible iOS Simulator runtime.
Unzip the archive, boot an iOS Simulator, and install the app with:
  xcrun simctl install booted Cinue.app
Launch Cinue from the Simulator home screen.

This package is for iOS Simulator. It cannot be installed on an iPhone or run as a native macOS application.
INFO
if [[ "$provenance" == dirty ]]; then
  printf '\nA modified source checkout identifies only the base commit and is suitable for local review only.\n' >> "$tmp/Cinue-iOS-Simulator-arm64.txt"
fi
(cd "$tmp" && shasum -a 256 Cinue-iOS-Simulator-arm64.zip > Cinue-iOS-Simulator-arm64.zip.sha256)
mv "$tmp/Cinue-iOS-Simulator-arm64.zip" "$archive"
mv "$tmp/Cinue-iOS-Simulator-arm64.zip.sha256" "$checksum"
mv "$tmp/Cinue-iOS-Simulator-arm64.txt" "$metadata"
printf 'Created %s\n' "$archive" "$checksum" "$metadata"
