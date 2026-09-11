#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -module-cache-path /tmp/duo-swift-cache Sources/EffectModel.swift Sources/EffectProcessor.swift Tests/GradientBlurCheck.swift -o .build/gradient-check
.build/gradient-check
