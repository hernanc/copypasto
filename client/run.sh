#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Copypasto"
PROJECT="${SCRIPT_DIR}/Copypasto.xcodeproj"
BUILD_DIR="${SCRIPT_DIR}/.build"
APP_PATH="${BUILD_DIR}/Build/Products/Debug/Copypasto.app"

echo "==> Building ${SCHEME}..."
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination "platform=macOS" \
    -derivedDataPath "${BUILD_DIR}" \
    build \
    2>&1 | tail -5

echo "==> Launching Copypasto..."
open "${APP_PATH}"
