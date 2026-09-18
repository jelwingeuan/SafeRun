#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
if [[ $# -ne 2 || ( "$2" != --signed && "$2" != --unsigned ) ]]; then
  echo "Usage: Scripts/verify_dmg.sh <dmg> --signed|--unsigned" >&2; exit 2
fi
hdiutil verify "$1"
MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/saferun-dmg.XXXXXX")
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then hdiutil detach "$MOUNT"; fi
  rmdir "$MOUNT"
}
trap cleanup EXIT
hdiutil attach "$1" -readonly -nobrowse -mountpoint "$MOUNT"
MOUNTED=1
APP="$MOUNT/$APP_NAME.app"
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]]
test -x "$APP/Contents/MacOS/$APP_NAME"
test -s "$APP/Contents/Resources/Icon.icns"
for arch in arm64 x86_64; do
  lipo -verify_arch "$arch" "$APP/Contents/MacOS/$APP_NAME"
done
PLIST="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" == "$MARKETING_VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$PLIST")" == "$BUILD_NUMBER" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST")" == "$MACOS_MIN_VERSION" ]]
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$2" == --signed ]]; then
  "$ROOT/Scripts/verify_signature.sh" "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
else
  test -s "$MOUNT/UNSIGNED-DIAGNOSTIC.txt"
  [[ "$(plutil -extract SafeRunDistribution raw -o - "$PLIST")" == unsigned-diagnostic ]]
fi
echo "Verified DMG contents, metadata, universal executable, and Applications link."
