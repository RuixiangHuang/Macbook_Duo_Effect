#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Duo Effect.app"
# A certificate-bound designated requirement preserves TCC identity across builds.
# Never silently fall back to ad-hoc signing for a screen-capture application.
if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}) .*/\1/p')"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$IDENTITY_COUNT" != "1" ]]; then
    echo 'Set CODE_SIGN_IDENTITY to an Apple Development or Developer ID identity from security find-identity -v -p codesigning.' >&2
    exit 1
  fi
  CODE_SIGN_IDENTITY="$IDENTITIES"
fi
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  echo 'Ad-hoc signing is not supported: it invalidates stored screen-recording grants after rebuilds.' >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path /tmp/duo-swift-cache Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework IOKit \
  -framework ScreenCaptureKit -framework CoreImage -framework Metal -framework MetalKit \
  -o "$APP/Contents/MacOS/DuoEffect"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DuoEffect</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>local.ruixiang.macbookduo</string>
<key>CFBundleName</key><string>Duo Effect</string>
<key>CFBundleDisplayName</key><string>Duo Effect</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>在内存中实时模糊内置显示器，不保存或上传屏幕内容。</string>
</dict></plist>
PLIST
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP"
./scripts/check-signature.sh "$APP"
echo "Built: $APP"
