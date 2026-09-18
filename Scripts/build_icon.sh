#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-$ROOT/Icon.icns}
mkdir -p "$ROOT/.build"
ICON_WORK=$(mktemp -d "$ROOT/.build/icon.XXXXXX")
trap 'rm -rf -- "$ICON_WORK"' EXIT
mkdir "$ICON_WORK/Icon.iconset"
swift "$ROOT/Scripts/draw_icon.swift" "$ICON_WORK/Icon.iconset"
iconutil --convert icns --output "$OUTPUT" "$ICON_WORK/Icon.iconset"
test -s "$OUTPUT"
