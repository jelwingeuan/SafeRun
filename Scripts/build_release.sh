#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
UNSIGNED=0
case "${1:-}" in
  '') ;;
  --unsigned) UNSIGNED=1 ;;
  --help|-h) echo "Usage: Scripts/build_release.sh [--unsigned]"; exit 0 ;;
  *) echo "Usage: Scripts/build_release.sh [--unsigned]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
if [[ "$UNSIGNED" == 0 ]]; then
  : "${APP_IDENTITY:?Public releases require a Developer ID Application identity; --unsigned is local diagnostics only}"
  : "${APPLE_API_KEY_ID:?Missing APPLE_API_KEY_ID}"
  : "${APPLE_API_ISSUER_ID:?Missing APPLE_API_ISSUER_ID}"
  : "${APPLE_API_KEY_PATH:?Missing APPLE_API_KEY_PATH (private .p8 file)}"
  test -s "$APPLE_API_KEY_PATH"
fi
[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 2
[[ "$MACOS_MIN_VERSION" == 14.0 ]] || { echo "ERROR: macOS 14.0 deployment target required." >&2; exit 1; }
BASE="$APP_NAME-$MARKETING_VERSION"
if [[ "$UNSIGNED" == 1 ]]; then BASE="$BASE-UNSIGNED"; fi
DESTINATION="$ROOT/dist/$BASE"
if [[ -e "$DESTINATION" ]]; then
  echo "ERROR: Output already exists: $DESTINATION. Move it aside before rebuilding." >&2; exit 1
fi
mkdir -p "$ROOT/dist" "$ROOT/.build"
WORK=$(mktemp -d "$ROOT/.build/release.XXXXXX")
finish() {
  result=$?
  if [[ $result -eq 0 ]]; then
    rm -rf -- "$WORK"
  else
    echo "Release failed; diagnostic files retained at $WORK. Nothing published to $DESTINATION." >&2
  fi
}
trap finish EXIT
mkdir "$WORK/artifacts" "$WORK/image"
PACKAGE_ARGS=(release)
if [[ "$UNSIGNED" == 1 ]]; then PACKAGE_ARGS+=(--unsigned); fi
ARCHES="arm64 x86_64" PACKAGE_OUTPUT_DIR="$WORK" "$ROOT/Scripts/package_app.sh" "${PACKAGE_ARGS[@]}"
APP="$WORK/$APP_NAME.app"
for arch in arm64 x86_64; do
  lipo -verify_arch "$arch" "$APP/Contents/MacOS/$APP_NAME"
done
if [[ "$UNSIGNED" == 0 ]]; then
  ditto -c -k --keepParent "$APP" "$WORK/notarization.zip"
  "$ROOT/Scripts/notarize.sh" "$WORK/notarization.zip" "$WORK/artifacts/app-notarization.json"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  "$ROOT/Scripts/verify_signature.sh" "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
ditto "$APP" "$WORK/image/$APP_NAME.app"
ln -s /Applications "$WORK/image/Applications"
if [[ "$UNSIGNED" == 1 ]]; then
  printf '%s\n' 'UNSIGNED DIAGNOSTIC BUILD — NOT FOR PUBLIC DISTRIBUTION.' \
    'Ad-hoc signature only. No Developer ID, notarization, or Gatekeeper approval.' > "$WORK/image/UNSIGNED-DIAGNOSTIC.txt"
fi
DMG="$WORK/artifacts/$BASE.dmg"
VOLUME="$APP_NAME $MARKETING_VERSION"
if [[ "$UNSIGNED" == 1 ]]; then VOLUME="$VOLUME UNSIGNED"; fi
hdiutil create -volname "$VOLUME" -srcfolder "$WORK/image" -fs HFS+ -format UDZO "$DMG"
if [[ "$UNSIGNED" == 0 ]]; then
  codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG"
  "$ROOT/Scripts/verify_signature.sh" "$DMG"
  "$ROOT/Scripts/notarize.sh" "$DMG" "$WORK/artifacts/dmg-notarization.json"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  "$ROOT/Scripts/verify_signature.sh" "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
"$ROOT/Scripts/verify_dmg.sh" "$DMG" "$([[ "$UNSIGNED" == 1 ]] && echo --unsigned || echo --signed)"
(
  cd "$WORK/artifacts"
  shasum -a 256 "$BASE.dmg" > "$BASE.dmg.sha256"
  shasum -a 256 --check "$BASE.dmg.sha256"
)
mv "$WORK/artifacts" "$DESTINATION"
echo "Release artifacts: $DESTINATION"
if [[ "$UNSIGNED" == 1 ]]; then echo "UNSIGNED DIAGNOSTIC ONLY — not a public release."; fi
