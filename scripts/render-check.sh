#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path /tmp/duo-swift-cache Sources/EffectModel.swift Sources/EffectProcessor.swift Tests/RenderCheck.swift -o .build/render-check
.build/render-check
