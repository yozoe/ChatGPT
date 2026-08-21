#!/bin/zsh

# Builds a Release app and packages it as an unsigned DMG without launching it.
# Signing and notarization are intentionally separate release steps.

set -euo pipefail

usage() {
  print "Usage: ./build_dmg.sh [--output <path-to-dmg>]"
  print "Builds the macOS Release app and creates an unsigned DMG without opening it."
}

script_dir="${0:A:h}"
release_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*$/\1/p' "$script_dir/pubspec.yaml" | head -n 1)"
if [[ -z "$release_version" ]]; then
  print -u2 "Unable to read the application version from pubspec.yaml."
  exit 1
fi

output_path="$script_dir/dist/Codex-Desk-$release_version.dmg"
case "${1:-}" in
  "") ;;
  --output)
    if [[ -z "${2:-}" || "${3:-}" != "" ]]; then
      usage >&2
      exit 64
    fi
    output_path="${2:A}"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

source_app="$script_dir/build/macos/Build/Products/Release/chatgpt.app"
output_directory="${output_path:h}"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/codex-desk-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

cd "$script_dir"
flutter build macos --release

if [[ ! -d "$source_app" ]]; then
  print -u2 "Build succeeded but the macOS application was not found: $source_app"
  exit 1
fi

mkdir -p "$output_directory"
rm -f "$output_path"
/usr/bin/ditto "$source_app" "$staging_directory/Codex Desk.app"
ln -s /Applications "$staging_directory/Applications"
hdiutil create \
  -volname "Codex Desk" \
  -srcfolder "$staging_directory" \
  -ov \
  -format UDZO \
  "$output_path"
hdiutil verify "$output_path"
print "Created unsigned DMG: $output_path"
