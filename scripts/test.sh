#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path /tmp/duo-swift-cache Sources/EffectModel.swift Tests/main.swift -o .build/model-tests
.build/model-tests
