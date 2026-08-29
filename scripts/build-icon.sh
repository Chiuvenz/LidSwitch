#!/bin/zsh
set -euo pipefail

lid_switch_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
lid_switch_icon_source="$lid_switch_project_dir/Assets/AppIcon.png"
lid_switch_icon_output="$lid_switch_project_dir/Resources/AppIcon.icns"
lid_switch_icon_work_dir="$(mktemp -d /tmp/LidSwitch.iconset.XXXXXX)"
lid_switch_iconset="$lid_switch_icon_work_dir/AppIcon.iconset"

trap 'rm -rf "$lid_switch_icon_work_dir"' EXIT
mkdir -p "$lid_switch_iconset"

sips -z 16 16 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_16x16.png"
sips -z 32 32 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_16x16@2x.png"
sips -z 32 32 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_32x32.png"
sips -z 64 64 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_32x32@2x.png"
sips -z 128 128 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_128x128.png"
sips -z 256 256 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_128x128@2x.png"
sips -z 256 256 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_256x256.png"
sips -z 512 512 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_256x256@2x.png"
sips -z 512 512 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_512x512.png"
sips -z 1024 1024 "$lid_switch_icon_source" --out "$lid_switch_iconset/icon_512x512@2x.png"
iconutil -c icns "$lid_switch_iconset" -o "$lid_switch_icon_output"

echo "$lid_switch_icon_output"
