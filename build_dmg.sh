#!/bin/zsh

# Builds a Release app and packages a DMG without launching it. When signing
# options are supplied, it also signs, notarizes, staples, and assesses it.

set -euo pipefail

usage() {
  print "Usage: ./build_dmg.sh [--output <path-to-dmg>] [--sign-identity <identity>] [--notary-profile <profile>]"
  print "Builds the macOS Release app and creates a DMG without opening it."
  print "  --sign-identity  Developer ID Application identity used for the app and DMG."
  print "  --notary-profile notarytool Keychain profile; requires --sign-identity."
  print "Environment fallbacks: CODEX_DESK_SIGN_IDENTITY and CODEX_DESK_NOTARY_PROFILE."
}

script_dir="${0:A:h}"
release_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*$/\1/p' "$script_dir/pubspec.yaml" | head -n 1)"
if [[ -z "$release_version" ]]; then
  print -u2 "Unable to read the application version from pubspec.yaml."
  exit 1
fi

output_path="$script_dir/dist/Codex-Desk-$release_version.dmg"
sign_identity="${CODEX_DESK_SIGN_IDENTITY:-}"
notary_profile="${CODEX_DESK_NOTARY_PROFILE:-}"
while (( $# > 0 )); do
  case "$1" in
    --output)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        exit 64
      fi
      output_path="${2:A}"
      shift 2
      ;;
    --sign-identity)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        exit 64
      fi
      sign_identity="$2"
      shift 2
      ;;
    --notary-profile)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        exit 64
      fi
      notary_profile="$2"
      shift 2
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
done

if [[ -n "$notary_profile" && -z "$sign_identity" ]]; then
  print -u2 "Notarization requires a Developer ID signing identity."
  exit 64
fi

source_app="$script_dir/build/macos/Build/Products/Release/chatgpt.app"
release_entitlements="$script_dir/macos/Runner/Release.entitlements"
output_directory="${output_path:h}"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/codex-desk-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

cd "$script_dir"
flutter build macos --release

if [[ ! -d "$source_app" ]]; then
  print -u2 "Build succeeded but the macOS application was not found: $source_app"
  exit 1
fi

if [[ -n "$sign_identity" ]]; then
  if [[ ! -f "$release_entitlements" ]]; then
    print -u2 "Release entitlements were not found: $release_entitlements"
    exit 1
  fi
  print "Signing application with Developer ID identity: $sign_identity"
  while IFS= read -r -d '' nested_code; do
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$sign_identity" \
      "$nested_code"
  done < <(
    /usr/bin/find "$source_app/Contents" -depth \
      \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.bundle' \) \
      -o -type f \( -name '*.dylib' -o -name '*.so' \) \) \
      -print0
  )
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$release_entitlements" \
    --sign "$sign_identity" \
    "$source_app"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$source_app"
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

if [[ -n "$sign_identity" ]]; then
  /usr/bin/codesign \
    --force \
    --timestamp \
    --sign "$sign_identity" \
    "$output_path"
  /usr/bin/codesign --verify --strict --verbose=2 "$output_path"
  hdiutil verify "$output_path"
fi

if [[ -n "$notary_profile" ]]; then
  print "Submitting DMG for Apple notarization..."
  /usr/bin/xcrun notarytool submit \
    "$output_path" \
    --keychain-profile "$notary_profile" \
    --wait
  /usr/bin/xcrun stapler staple "$output_path"
  /usr/bin/xcrun stapler validate "$output_path"
  /usr/sbin/spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$output_path"
  print "Created signed and notarized DMG: $output_path"
elif [[ -n "$sign_identity" ]]; then
  print "Created signed (not notarized) DMG: $output_path"
else
  print "Created unsigned DMG: $output_path"
fi
