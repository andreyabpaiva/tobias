#!/usr/bin/env bash
# Builds Tobias.app from the SwiftPM package. Needs only the Xcode Command Line Tools.
# Usage: scripts/build-app.sh [output-dir]   (default: ./build)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build}"
APP="$OUT/Tobias.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

cd "$ROOT"
echo "Building Tobias $VERSION (release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tobias" "$APP/Contents/MacOS/Tobias"

# App icon: the app draws it (pixel cat), iconutil packs the sizes Finder and the Dock use.
ICONSET="$OUT/Tobias.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$APP/Contents/MacOS/Tobias" --write-icon "$OUT/icon-1024.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$OUT/icon-1024.png"

# SwiftPM resource bundles (the catalog) go into Contents/Resources.
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.tobias.Tobias</string>
  <key>CFBundleName</key><string>Tobias</string>
  <key>CFBundleDisplayName</key><string>Tobias</string>
  <key>CFBundleExecutable</key><string>Tobias</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run a locally built app, no developer account needed.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
