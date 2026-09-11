#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Regenerates Resources/AppIcon.icns from the masked 1024pt Resources/AppIcon.png.
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png \
    --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Built: Resources/AppIcon.icns"
