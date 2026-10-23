#!/usr/bin/env bash
# Build dist/Focus-<version>.dmg: a drag-to-Applications installer with a custom background.
#
# Usage: scripts/build-dmg.sh [--no-build]
#   --no-build  package the existing build/Focus.app instead of running scripts/build.sh first.
#
# Idempotent: every run replaces dist/Focus-<version>.dmg. The Finder window layout is
# best-effort. If Finder automation is not permitted, the DMG is still built, without the layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NO_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=1 ;;
    -h|--help)
      sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' extension/manifest.json | head -n 1)"
if [[ -z "$VERSION" ]]; then
  echo "Cannot read the version from extension/manifest.json" >&2
  exit 1
fi

APP="$ROOT/build/Focus.app"
DMG="$ROOT/dist/Focus-$VERSION.dmg"
VOLNAME="Focus"
BG_DIR="$ROOT/assets/dmg"
BG_TIFF="$BG_DIR/background.tiff"

# Installer window layout in points. It matches the background image and the icon slots in it.
WIN_X=200
WIN_Y=120
WIN_W=660
WIN_H=400
ICON_SIZE=128
APP_POS_X=170
APP_POS_Y=190
APPS_POS_X=490
APPS_POS_Y=190

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "==> Building Focus $VERSION"
  "$ROOT/scripts/build.sh"
fi

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP. Run scripts/build.sh first, or drop --no-build." >&2
  exit 1
fi

# Background: the committed TIFF bundles the 1x and 2x PNGs. Regenerate it only if it is missing or stale.
if [[ ! -f "$BG_TIFF" || "$BG_DIR/background.png" -nt "$BG_TIFF" || "$BG_DIR/background@2x.png" -nt "$BG_TIFF" ]]; then
  echo "==> Rendering DMG background"
  swift "$BG_DIR/make-background.swift" "$BG_DIR" >/dev/null
  tiffutil -cathidpicheck "$BG_DIR/background.png" "$BG_DIR/background@2x.png" -out "$BG_TIFF" >/dev/null
fi

if [[ -e "/Volumes/$VOLNAME" ]]; then
  echo "A volume named \"$VOLNAME\" is already mounted at /Volumes/$VOLNAME. Eject it and run again." >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/focus-dmg.XXXXXX")"
STAGE="$WORK/stage"
RW_DMG="$WORK/Focus-rw.dmg"
DEVICE=""

cleanup() {
  local status=$?
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || hdiutil detach "$DEVICE" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT INT TERM

echo "==> Staging $VOLNAME $VERSION"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Focus.app"
ln -s /Applications "$STAGE/Applications"
cp "$BG_TIFF" "$STAGE/.background/background.tiff"
ICNS="$APP/Contents/Resources/AppIcon.icns"

# Writable image sized from the staging folder plus headroom for Finder's .DS_Store and the icon.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 32 ))
rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -size "${SIZE_MB}m" \
  -fs HFS+ -format UDRW -ov "$RW_DMG" -quiet

echo "==> Mounting read-write image"
MOUNT_INFO="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -nobrowse)"
DEVICE="$(echo "$MOUNT_INFO" | awk 'NR==1 {print $1}')"
MOUNT_POINT="/Volumes/$VOLNAME"
if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "Mounted volume not found at $MOUNT_POINT" >&2
  exit 1
fi

# Finder window layout. Best-effort: a denied Automation permission must not fail the build.
LAYOUT_APPLIED=0
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set the bounds of theWindow to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
    set theOptions to the icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to $ICON_SIZE
    set text size of theOptions to 13
    set background picture of theOptions to file ".background:background.tiff"
    set position of item "Focus.app" of theWindow to {$APP_POS_X, $APP_POS_Y}
    set position of item "Applications" of theWindow to {$APPS_POS_X, $APPS_POS_Y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  LAYOUT_APPLIED=1
else
  echo "WARNING: Finder layout not applied (Finder automation may be denied for your terminal)." >&2
  echo "         The DMG still works, but the window will not have the custom background or icon positions." >&2
  echo "         Grant Automation access under System Settings > Privacy & Security > Automation, then rerun." >&2
fi

# Volume icon. Install it after the Finder pass: Finder deletes a .VolumeIcon.icns that is
# already on the volume when the window layout runs.
if [[ -f "$ICNS" ]]; then
  cp "$ICNS" "$MOUNT_POINT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_POINT" 2>/dev/null || echo "NOTE: SetFile unavailable, volume icon flag not set." >&2
fi

sync
for attempt in 1 2 3 4 5; do
  if hdiutil detach "$DEVICE" -quiet 2>/dev/null; then
    DEVICE=""
    break
  fi
  sleep 2
done
if [[ -n "$DEVICE" ]]; then
  hdiutil detach "$DEVICE" -force -quiet
  DEVICE=""
fi

echo "==> Converting to compressed UDZO"
mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
codesign --force --sign - "$DMG"

SIZE="$(du -h "$DMG" | cut -f1)"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "==> Done: $DMG"
echo "  size:   $SIZE"
echo "  sha256: $SHA"
if [[ "$LAYOUT_APPLIED" -eq 1 ]]; then
  echo "  finder layout: applied"
else
  echo "  finder layout: NOT applied (see warning above)"
fi
