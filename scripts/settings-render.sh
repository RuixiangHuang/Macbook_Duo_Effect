#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build docs
swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path /tmp/duo-swift-cache \
  Sources/Localization.swift Sources/DebugLog.swift Sources/EffectModel.swift Sources/LidSensor.swift \
  Sources/BlurOverlay.swift Sources/EffectProcessor.swift Sources/AppController.swift Tests/SettingsRender.swift \
  -framework AppKit -framework SwiftUI -framework IOKit \
  -framework ScreenCaptureKit -framework CoreImage -framework Metal -framework MetalKit \
  -o .build/settings-render
.build/settings-render
