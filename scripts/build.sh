#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Focus.app"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/extension/manifest.json" | head -n 1)"
if [[ -z "$VERSION" ]]; then
  echo "Cannot read the version from extension/manifest.json" >&2
  exit 1
fi

cd "$ROOT"
# Universal binary (arm64 + x86_64).
ARCH_FLAGS=(--arch arm64 --arch x86_64)
echo "==> Building Focus $VERSION (release, arm64 + x86_64)"
swift build -c release --product Focus "${ARCH_FLAGS[@]}"

BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Focus" "$APP/Contents/MacOS/Focus"
# Drop debug stabs, which otherwise carry the absolute source path (/Users/...). Global symbols stay for crash logs.
strip -S "$APP/Contents/MacOS/Focus"
if grep -a -q -F "$ROOT" "$APP/Contents/MacOS/Focus"; then
  echo "Focus binary still embeds the build path $ROOT" >&2
  exit 1
fi
for arch in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/Focus" -verify_arch "$arch" || {
    echo "Focus binary is missing the $arch slice" >&2
    exit 1
  }
done

# App icon: compile the committed Icon Composer source (assets/AppIcon.icon) into
# Assets.car (light, dark and tinted appearances) plus an AppIcon.icns fallback.
# Regenerating the icon is not needed here; edit the .icon in Icon Composer instead.
echo "==> Compiling app icon"
mkdir -p "$APP/Contents/Resources"
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
xcrun actool "$ROOT/assets/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
test -f "$APP/Contents/Resources/Assets.car"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.pol.focus</string>
    <key>CFBundleName</key>
    <string>Focus</string>
    <key>CFBundleExecutable</key>
    <string>Focus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.5.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
</dict>
</plist>
PLIST

# Keep the app version in lockstep with the extension version.
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Browser extension, copied out of the bundle by Settings > General > Show Browser Extension.
cp -R "$ROOT/extension" "$APP/Contents/Resources/extension"
find "$APP/Contents/Resources/extension" -name .DS_Store -delete

codesign --force --sign - "$APP"

echo "==> Built $APP"
