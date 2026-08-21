#!/bin/zsh

# Builds Codex Desk, installs it as /Applications/Codex Desk.app, then opens it.
# The replacement step prompts for an administrator password when necessary.

set -euo pipefail

usage() {
  print "Usage: ./install_macos.sh [--build-only | --install-only]"
  print "  --build-only    Build the Release app without installing or opening it."
  print "  --install-only  Install the existing Release app without rebuilding it."
}

mode="install"
case "${1:-}" in
  "") ;;
  --build-only) mode="build-only" ;;
  --install-only) mode="install-only" ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

script_dir="${0:A:h}"
source_app="$script_dir/build/macos/Build/Products/Release/chatgpt.app"
target_app="/Applications/Codex Desk.app"
install_state_dir="$HOME/Library/Application Support/Codex Desk"
install_fingerprint_file="$install_state_dir/install-fingerprint"
bundle_identifier="com.yozoe.chatgpt"
project_input_paths=(
  "$script_dir/lib"
  "$script_dir/assets"
  "$script_dir/macos/Runner"
  "$script_dir/macos/Runner.xcodeproj"
  "$script_dir/macos/Podfile"
  "$script_dir/macos/Podfile.lock"
  "$script_dir/macos/Flutter/Flutter-Debug.xcconfig"
  "$script_dir/macos/Flutter/Flutter-Release.xcconfig"
  "$script_dir/../private/yeknom-ui-kit"
)

existing_project_input_paths=()
for project_input_path in "${project_input_paths[@]}"; do
  if [[ -e "$project_input_path" ]]; then
    existing_project_input_paths+=("$project_input_path")
  fi
done

project_fingerprint="$({
  if (( ${#existing_project_input_paths[@]} > 0 )); then
    find "${existing_project_input_paths[@]}" -type f -exec shasum {} +
  fi
  shasum "$script_dir/pubspec.yaml" "$script_dir/pubspec.lock" "$script_dir/install_macos.sh"
} | LC_ALL=C sort | shasum | awk '{print $1}')"

stop_running_app() {
  if ! /usr/bin/pgrep -f "$target_app/Contents/MacOS/" >/dev/null; then
    return
  fi

  print "Closing the currently running Codex Desk..."
  /usr/bin/osascript -e "tell application id \"$bundle_identifier\" to quit" || true
  for _ in {1..50}; do
    if ! /usr/bin/pgrep -f "$target_app/Contents/MacOS/" >/dev/null; then
      return
    fi
    sleep 0.1
  done

  print -u2 "Codex Desk is still running. Close it manually, then rerun this script."
  exit 1
}

if [[ "$mode" == "install" && -d "$target_app" && -f "$install_fingerprint_file" ]]; then
  installed_fingerprint="$(<"$install_fingerprint_file")"
  if [[ "$installed_fingerprint" == "$project_fingerprint" ]]; then
    stop_running_app
    open -n "$target_app"
    print "No application source changes; restarted existing installation: $target_app"
    exit 0
  fi
fi

cd "$script_dir"
built_current_source=false
if [[ "$mode" != "install-only" ]]; then
  flutter build macos --release
  built_current_source=true
fi

if [[ ! -d "$source_app" ]]; then
  print -u2 "The macOS Release application was not found: $source_app"
  exit 1
fi

if [[ "$mode" == "build-only" ]]; then
  print "Built Release application: $source_app"
  exit 0
fi

stop_running_app
if [[ -e "$target_app" ]]; then
  sudo /bin/rm -rf "$target_app"
fi
sudo /usr/bin/ditto "$source_app" "$target_app"
if [[ "$built_current_source" == true ]]; then
  mkdir -p "$install_state_dir"
  print -r -- "$project_fingerprint" > "$install_fingerprint_file"
fi

# The app keeps its bundle identifier across upgrades, so Finder and the Dock
# can otherwise retain the previous icon after the application bundle changes.
sudo /usr/bin/touch "$target_app"
/usr/bin/killall Dock || true
/usr/bin/killall Finder || true

open -n "$target_app"
print "Installed and opened: $target_app"
