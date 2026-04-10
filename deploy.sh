#!/usr/bin/env bash
set -euo pipefail

# Configuration
AWS_REGION="us-east-1"
ECR_REPO="copypasto-server"
ECS_CLUSTER="copypasto-prod"
ECS_SERVICE="copypasto-prod-server"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

echo "==> Logging into ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "==> Building and pushing Docker image (linux/amd64)..."
docker buildx build --platform linux/amd64 -t "${ECR_URI}:latest" --push server/

echo "==> Deploying to ECS..."
aws ecs update-service \
    --cluster "${ECS_CLUSTER}" \
    --service "${ECS_SERVICE}" \
    --force-new-deployment \
    --region "${AWS_REGION}" \
    --no-cli-pager

echo "==> Deployment initiated. Monitor at:"
echo "    https://${AWS_REGION}.console.aws.amazon.com/ecs/v2/clusters/${ECS_CLUSTER}/services/${ECS_SERVICE}/deployments"
