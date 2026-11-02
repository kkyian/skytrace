#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$SOURCE/Sources/Skytrace/Resources/catalog.sqlite" ]; then
    python3 "$SOURCE/scripts/update-catalog.py"
fi
DEST="${1:-$SOURCE/..}"
cd "$SOURCE"
if [ -n "${SKYTRACE_BUILD_PATH:-}" ]; then
    swift build --scratch-path "$SKYTRACE_BUILD_PATH" -c release
    BIN="$(swift build --scratch-path "$SKYTRACE_BUILD_PATH" -c release --show-bin-path)"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)"
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/skytrace-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Skytrace.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Skytrace" "$APP/Contents/MacOS/Skytrace"
cp -R "$BIN/Skytrace_Skytrace.bundle" "$APP/Contents/Resources/"
if [ -f "$SOURCE/Artwork/AppIcon.icns" ]; then cp "$SOURCE/Artwork/AppIcon.icns" "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Skytrace</string>
<key>CFBundleIdentifier</key><string>io.skytrace.mac</string>
<key>CFBundleName</key><string>Skytrace</string>
<key>CFBundleDisplayName</key><string>Skytrace</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$DEST"
ditto --norsrc "$APP" "$DEST/Skytrace.app"
ditto -c -k --norsrc --keepParent "$APP" "$DEST/Skytrace-macOS.zip"
echo "Built $DEST/Skytrace.app and $DEST/Skytrace-macOS.zip"
