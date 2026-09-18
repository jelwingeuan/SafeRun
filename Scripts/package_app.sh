#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
CONF=release
UNSIGNED=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONF="$arg" ;;
    --unsigned) UNSIGNED=1 ;;
    *) echo "Usage: Scripts/package_app.sh [debug|release] [--unsigned]" >&2; exit 2 ;;
  esac
done
if [[ "$CONF" == debug ]]; then UNSIGNED=1; fi
if [[ "$UNSIGNED" == 0 && -z "${APP_IDENTITY:-}" ]]; then
  echo "ERROR: APP_IDENTITY must identify a Developer ID Application certificate. Use --unsigned only for local diagnostics." >&2
  exit 1
fi
if [[ "${SKIP_BUILD:-0}" != 0 ]]; then
  echo "ERROR: SKIP_BUILD is unsupported; packaging always builds the current sources." >&2
  exit 1
fi

read -r -a ARCH_LIST <<< "${ARCHES:-$(uname -m)}"
for arch in "${ARCH_LIST[@]}"; do
  case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 2 ;; esac
done
if [[ ${#ARCH_LIST[@]} == 0 || ${#ARCH_LIST[@]} -gt 2 ]]; then exit 2; fi

# Isolate packaging from tests and other contributors' builds in this checkout.
BUILD_DIR="$ROOT/.build/packaging"
BINARIES=()
PRODUCT_DIRS=()
for arch in "${ARCH_LIST[@]}"; do
  swift build --scratch-path "$BUILD_DIR" -c "$CONF" --arch "$arch" --product "$APP_NAME"
  product_dir=$(swift build --scratch-path "$BUILD_DIR" -c "$CONF" --arch "$arch" --show-bin-path)
  BINARIES+=("$product_dir/$APP_NAME")
  PRODUCT_DIRS+=("$product_dir")
done

# Release callers supply a fresh staging directory. Local builds replace only SafeRun.app.
OUTPUT_DIR=${PACKAGE_OUTPUT_DIR:-$ROOT}
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
APP="$OUTPUT_DIR/$APP_NAME.app"
if [[ "$APP_NAME" != SafeRun || -L "$APP" ]]; then
  echo "ERROR: Unsafe app output path." >&2; exit 1
fi
if [[ -e "$APP" ]]; then
  echo "Replacing generated app bundle: $APP"
  rm -rf -- "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#BINARIES[@]} -eq 1 ]]; then
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"
else
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
fi
chmod +x "$APP/Contents/MacOS/$APP_NAME"
for arch in "${ARCH_LIST[@]}"; do
  lipo -verify_arch "$arch" "$APP/Contents/MacOS/$APP_NAME"
done

# SwiftPM resource bundles belong in the app's canonical Contents/Resources directory.
shopt -s nullglob
for bundle in "${PRODUCT_DIRS[0]}/"*.bundle; do
  ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
shopt -u nullglob
"$ROOT/Scripts/build_icon.sh" "$APP/Contents/Resources/Icon.icns"

DISPLAY_NAME="$APP_NAME"
if [[ "$UNSIGNED" == 1 ]]; then DISPLAY_NAME="$APP_NAME (Unsigned Diagnostic)"; fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MACOS_MIN_VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © $COPYRIGHT_YEAR Jelwin. All rights reserved.</string>
  <key>CFBundleIconFile</key><string>Icon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SafeRunDistribution</key><string>$([[ "$UNSIGNED" == 1 ]] && echo unsigned-diagnostic || echo developer-id)</string>
  <key>GitCommit</key><string>$(git rev-parse HEAD)</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" "$ROOT/SafeRun.entitlements"
xattr -cr "$APP"
if [[ "$UNSIGNED" == 1 ]]; then
  echo "UNSIGNED DIAGNOSTIC: ad-hoc signed for local execution; not for public distribution."
  codesign --force --sign - --entitlements "$ROOT/SafeRun.entitlements" "$APP"
else
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    --entitlements "$ROOT/SafeRun.entitlements" "$APP"
  "$ROOT/Scripts/verify_signature.sh" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Created $APP"
