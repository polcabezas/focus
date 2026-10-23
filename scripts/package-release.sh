#!/usr/bin/env bash
# Build the universal app and assemble the downloadable release folder and zip under dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' extension/manifest.json | head -n 1)"
if [[ -z "$VERSION" ]]; then
  echo "Cannot read the version from extension/manifest.json" >&2
  exit 1
fi

NAME="Focus-$VERSION-macOS"
STAGE="$ROOT/dist/$NAME"
ZIP="$ROOT/dist/$NAME.zip"

echo "==> Building Focus $VERSION"
"$ROOT/scripts/build.sh"

echo "==> Assembling $STAGE"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/scripts"
cp -R build/Focus.app "$STAGE/Focus.app"
cp -R extension "$STAGE/extension"
find "$STAGE/extension" -name .DS_Store -delete
cp scripts/install.sh scripts/uninstall.sh scripts/lib.sh "$STAGE/scripts/"
cp LICENSE "$STAGE/LICENSE"
cat > "$STAGE/INSTALL.md" <<'MD'
# Focus

A macOS menu-bar app and browser extension that blocks distracting sites and apps during focus time.

## Requirements

- macOS 26 or later

## Install the app

1. Unzip the download.
2. Open Terminal, go to the unzipped folder and run:

   ```sh
   ./scripts/install.sh
   ```

   The script installs `Focus.app` into `~/Applications` and starts it at login. It needs no root access.
   It clears the quarantine flag on the app, because Focus is ad-hoc signed and not notarized.

If macOS still blocks the app ("cannot be opened"), open System Settings > Privacy & Security and click **Open Anyway**.

## Load the browser extension

- **Arc:** open `arc://extensions`, turn on **Developer mode**, click **Load unpacked** and choose the `extension/` folder.
- **Search:** open the extension settings in Search and choose the `extension/` folder.

## Uninstall

```sh
./scripts/uninstall.sh
```

Uninstall is refused while a block is active. `./scripts/uninstall.sh --force` overrides that.
Remove the browser extension yourself in Arc (`arc://extensions`) and in Search's extension settings.

Full documentation: https://github.com/polcabezas/focus
MD
chmod +x "$STAGE/scripts/"*.sh

codesign --verify --deep --strict "$STAGE/Focus.app"
ditto -c -k --keepParent "$STAGE" "$ZIP"

echo "==> Building DMG installer"
"$ROOT/scripts/build-dmg.sh" --no-build
DMG="$ROOT/dist/Focus-$VERSION.dmg"

echo "==> Release package"
echo "  folder: $STAGE"
echo "  zip:    $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  dmg:    $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$ZIP" "$DMG"
