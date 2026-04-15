#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Copypasto"
PROJECT="${SCRIPT_DIR}/Copypasto.xcodeproj"
BUILD_DIR="${SCRIPT_DIR}/.build-release"
APP_NAME="Copypasto.app"
DMG_NAME="Copypasto.dmg"

AWS_REGION="us-east-1"
S3_BUCKET="copypasto-prod-website"
S3_KEY="beta/latest.dmg"

echo "==> Building ${SCHEME} (Release)..."
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "${BUILD_DIR}" \
    build \
    2>&1 | tail -5

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
if [ ! -d "${APP_PATH}" ]; then
    echo "Error: Build product not found at ${APP_PATH}"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist")
echo "==> Built ${APP_NAME} v${VERSION} (${BUILD})"

DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
rm -f "${DMG_PATH}"

STAGING_DIR=$(mktemp -d)
trap 'rm -rf "${STAGING_DIR}"' EXIT
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "Copypasto" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" \
    > /dev/null

DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1 | xargs)
echo "==> DMG created: ${DMG_PATH} (${DMG_SIZE})"

echo "==> Uploading to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "${DMG_PATH}" "s3://${S3_BUCKET}/${S3_KEY}" \
    --region "${AWS_REGION}" \
    --content-type "application/x-apple-diskimage" \
    --cache-control "no-cache, no-store, must-revalidate"

VERSIONED_KEY="beta/Copypasto-${VERSION}-${BUILD}.dmg"
aws s3 cp "${DMG_PATH}" "s3://${S3_BUCKET}/${VERSIONED_KEY}" \
    --region "${AWS_REGION}" \
    --content-type "application/x-apple-diskimage" \
    --cache-control "public, max-age=604800"

echo "==> Invalidating CloudFront cache for /beta/*..."
CDN_DISTRIBUTION_ID="${CDN_DISTRIBUTION_ID:-}"
if [ -z "${CDN_DISTRIBUTION_ID}" ]; then
    CDN_DISTRIBUTION_ID=$(cd "${SCRIPT_DIR}/../terraform" && terraform output -raw website_cdn_id 2>/dev/null || true)
fi

if [ -n "${CDN_DISTRIBUTION_ID}" ]; then
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "${CDN_DISTRIBUTION_ID}" \
        --paths "/${S3_KEY}" "/${VERSIONED_KEY}" \
        --query "Invalidation.Id" \
        --output text)
    echo "==> CloudFront invalidation ${INVALIDATION_ID} created."
else
    echo "==> Warning: Could not determine CloudFront distribution ID. Skipping invalidation."
    echo "   Set CDN_DISTRIBUTION_ID env var or ensure Terraform outputs are accessible."
fi

echo ""
echo "Done! Beta published:"
echo "  Latest:    https://copypasto.com/${S3_KEY}"
echo "  Versioned: https://copypasto.com/${VERSIONED_KEY}"
