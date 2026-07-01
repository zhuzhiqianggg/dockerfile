#!/bin/bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

REGISTRY="swr.cn-east-3.myhuaweicloud.com/beosin-develop"
IMAGE_NAME="tag-image"
DATE_TAG=$(date +%Y%m%d)
PLATFORM="linux/amd64,linux/arm64"

DEFAULT_TAG="${REGISTRY}/${IMAGE_NAME}:${DATE_TAG}"
TAG="${DEFAULT_TAG}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) TAG="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [-t TAG] [--platform PLATFORM]"
            echo "  Default tag: ${DEFAULT_TAG}"
            echo "  Default platform: linux/amd64,linux/arm64"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "============================================"
echo " ${IMAGE_NAME} Docker Image Build"
echo "============================================"
echo " Image:    ${TAG}"
echo " Platform: ${PLATFORM}"
echo "============================================"

docker buildx build \
    --platform "${PLATFORM}" \
    -t "${TAG}" \
    --provenance=false --sbom=false \
    --push .

echo ""
echo "--- BUILD DONE ---"
echo "  ${TAG}"
