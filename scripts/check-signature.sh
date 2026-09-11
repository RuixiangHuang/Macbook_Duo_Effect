#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/Duo Effect.app}"
codesign --verify --deep --strict "$APP"
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
if [[ "$REQUIREMENT" == *'designated => cdhash'* ]]; then
  echo 'FAIL: signing identity is bound to this build hash; privacy grants break after rebuilds.' >&2
  exit 1
fi
if [[ "$REQUIREMENT" != *'identifier "local.ruixiang.macbookduo"'* || "$REQUIREMENT" != *'anchor apple generic'* ]]; then
  echo 'FAIL: expected a stable Apple certificate and application identifier.' >&2
  exit 1
fi
echo 'PASS: valid signature with stable Apple certificate + application identifier.'
