#!/bin/bash

# ============================================
# macOS AppIcon Generator
# Native Apple Tools Version
#
# Usage:
#   ./make_icon.sh AppIcon.png
# ============================================

APP_ICON="$1"

if [ -z "$APP_ICON" ]; then
  echo "Usage: ./make_icon.sh AppIcon.png"
  exit 1
fi

if [ ! -f "$APP_ICON" ]; then
  echo "File not found: $APP_ICON"
  exit 1
fi

ICONSET="AppIcon.iconset"
OUTPUT="AppIcon.icns"

echo "Source: $APP_ICON"

rm -rf "$ICONSET"
mkdir "$ICONSET"

echo "Generating iconset..."

# Small
sips -z 16 16     "$APP_ICON" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$APP_ICON" --out "$ICONSET/icon_16x16@2x.png"

# Medium
sips -z 32 32     "$APP_ICON" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$APP_ICON" --out "$ICONSET/icon_32x32@2x.png"

# Large
sips -z 128 128   "$APP_ICON" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$APP_ICON" --out "$ICONSET/icon_128x128@2x.png"

# Extra Large
sips -z 256 256   "$APP_ICON" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$APP_ICON" --out "$ICONSET/icon_256x256@2x.png"

# Retina
sips -z 512 512   "$APP_ICON" --out "$ICONSET/icon_512x512.png"
cp "$APP_ICON" "$ICONSET/icon_512x512@2x.png"

echo "Creating $OUTPUT..."

iconutil -c icns "$ICONSET" -o "$OUTPUT"

echo ""
echo "Done!"
echo "Generated:"
echo "  $OUTPUT"
echo ""
echo "Preview:"
echo "  qlmanage -p $OUTPUT"