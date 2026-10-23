#!/usr/bin/env bash
# Rasterizes the browser extension icons from the SVG sources in assets/extension/.
# Usage: bash assets/make-extension-icons.sh   (run from anywhere)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/extension"
OUT="$ROOT/extension/icons"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"
sips -s format png "$SRC/icon-full.svg" --out "$TMP/full.png" >/dev/null
sips -s format png "$SRC/icon-small.svg" --out "$TMP/small.png" >/dev/null

# 16 and 32 px use the simplified glyph (thicker ring, no glow); 48 and 128 use the full glyph.
for px in 16 32; do
    sips -z "$px" "$px" "$TMP/small.png" --out "$OUT/icon$px.png" >/dev/null
done
for px in 48 128; do
    sips -z "$px" "$px" "$TMP/full.png" --out "$OUT/icon$px.png" >/dev/null
done
ls -l "$OUT"/icon*.png
