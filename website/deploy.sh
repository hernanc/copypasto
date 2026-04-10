#!/usr/bin/env bash
set -euo pipefail

# Configuration
AWS_REGION="us-east-1"
S3_BUCKET="copypasto-prod-website"
WEBSITE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Get CloudFront distribution ID from Terraform outputs (or override via env)
if [ -z "${CDN_DISTRIBUTION_ID:-}" ]; then
  echo "==> Reading CloudFront distribution ID from Terraform..."
  CDN_DISTRIBUTION_ID=$(cd "${WEBSITE_DIR}/../terraform" && terraform output -raw website_cdn_id 2>/dev/null || true)
fi

if [ -z "${CDN_DISTRIBUTION_ID:-}" ]; then
  echo "Error: CDN_DISTRIBUTION_ID not set and could not read from Terraform outputs."
  echo "Set it manually: CDN_DISTRIBUTION_ID=EXXXX ./deploy.sh"
  exit 1
fi

echo "==> Syncing website to s3://${S3_BUCKET}..."

# Sync HTML files with short cache
aws s3 sync "${WEBSITE_DIR}" "s3://${S3_BUCKET}" \
  --region "${AWS_REGION}" \
  --exclude ".DS_Store" \
  --exclude "deploy.sh" \
  --exclude "README.md" \
  --exclude "*.html" \
  --exclude "*.xml" \
  --exclude "robots.txt" \
  --cache-control "public, max-age=86400, s-maxage=604800" \
  --delete

# Sync HTML, XML, robots with short cache for quick updates
aws s3 sync "${WEBSITE_DIR}" "s3://${S3_BUCKET}" \
  --region "${AWS_REGION}" \
  --exclude "*" \
  --include "*.html" \
  --include "*.xml" \
  --include "robots.txt" \
  --cache-control "public, max-age=300, s-maxage=3600"

echo "==> Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "${CDN_DISTRIBUTION_ID}" \
  --paths "/*" \
  --query "Invalidation.Id" \
  --output text)

echo "==> Invalidation ${INVALIDATION_ID} created."
echo ""
echo "Done. Site deployed to https://copypasto.com"
echo "CloudFront invalidation may take 1-2 minutes to propagate."
