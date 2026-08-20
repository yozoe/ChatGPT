#!/bin/zsh

# Builds Codex Desk, installs it as /Applications/Codex Desk.app, then opens it.
# The replacement step prompts for an administrator password when necessary.

set -euo pipefail

script_dir="${0:A:h}"
source_app="$script_dir/build/macos/Build/Products/Release/chatgpt.app"
target_app="/Applications/Codex Desk.app"

cd "$script_dir"
flutter build macos --release

if [[ ! -d "$source_app" ]]; then
  print -u2 "Build succeeded but the macOS application was not found: $source_app"
  exit 1
fi

if [[ -e "$target_app" ]]; then
  sudo /bin/rm -rf "$target_app"
fi
sudo /usr/bin/ditto "$source_app" "$target_app"

open -n "$target_app"
print "Installed and opened: $target_app"
