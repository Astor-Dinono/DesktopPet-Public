#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/test-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/test-swift-cache"
swift test --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache" \
    --config-path "$PROJECT_DIR/.build/config" --security-path "$PROJECT_DIR/.build/security" \
    --manifest-cache local --scratch-path "$PROJECT_DIR/.build-tests" -debug-info-format none
