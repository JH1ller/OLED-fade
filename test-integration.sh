#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -D INTEGRATION_TEST Sources/IdlePolicy.swift Sources/main.swift \
    -framework AppKit -framework CoreGraphics -o build/OverlayIntegrationTests
build/OverlayIntegrationTests
