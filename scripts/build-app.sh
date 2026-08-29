#!/bin/zsh
set -euo pipefail

lid_switch_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
lid_switch_app_dir="$lid_switch_project_dir/dist/LidSwitch.app"
lid_switch_contents_dir="$lid_switch_app_dir/Contents"

cd "$lid_switch_project_dir"
swift build -c release --product LidSwitch

mkdir -p "$lid_switch_contents_dir/MacOS"
mkdir -p "$lid_switch_contents_dir/Resources"
cp "$lid_switch_project_dir/.build/release/LidSwitch" "$lid_switch_contents_dir/MacOS/LidSwitch"
cp "$lid_switch_project_dir/Resources/Info.plist" "$lid_switch_contents_dir/Info.plist"
cp "$lid_switch_project_dir/Resources/AppIcon.icns" "$lid_switch_contents_dir/Resources/AppIcon.icns"
codesign --force --deep --sign - "$lid_switch_app_dir"

echo "$lid_switch_app_dir"
