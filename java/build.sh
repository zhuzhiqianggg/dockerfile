#!/bin/bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

REGISTRY="swr.cn-east-3.myhuaweicloud.com/beosin-develop"
IMAGE_NAME="jdk"
DATE_TAG=$(date +%Y%m%d)
JDK_VERSION=$(grep -m1 'ARG JDK_VERSION=' Dockerfile | sed 's/.*=//')
PLATFORM="linux/amd64,linux/arm64"

DEFAULT_TAG="${REGISTRY}/${IMAGE_NAME}:${JDK_VERSION}_JMX_${DATE_TAG}"
TAG="${DEFAULT_TAG}"

SERVICE_NAME="test-app"
SERVICE_PORT="8080"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) TAG="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        -n) SERVICE_NAME="$2"; shift 2 ;;
        -p) SERVICE_PORT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [-t TAG] [-n NAME] [-p PORT] [--platform PLATFORM]"
            echo "  Default tag: ${DEFAULT_TAG}"
            echo "  Default platform: linux/amd64,linux/arm64"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "============================================"
echo " Java Docker Base - Build & Test"
echo "============================================"
echo " Image:     ${TAG}"
echo " JDK:       ${JDK_VERSION}"
echo " Platform:  ${PLATFORM}"
echo " App:       ${SERVICE_NAME}"
echo " Port:      ${SERVICE_PORT}"
echo "============================================"

echo ""
echo "[1/4] Building base image..."
docker buildx build \
    --platform "${PLATFORM}" \
    -t "${TAG}" \
    --build-arg JDK_VERSION="${JDK_VERSION}" \
    --provenance=false --sbom=false \
    --push .

echo ""
echo "[2/4] Building test app (Maven in Docker)..."
docker run --rm \
    -v "$(pwd)/test-app:/app" \
    -v maven-repo:/root/.m2 \
    -w /app \
    maven:3.8.5-openjdk-8 \
    mvn clean package -q -DskipTests

JAR="test-app/target/test-app.jar"
if [[ ! -f "${JAR}" ]]; then
    echo "ERROR: ${JAR} not found after Maven build!"
    exit 1
fi
echo "       Jar: ${JAR} ($(du -h "${JAR}" | cut -f1))"

echo ""
echo "[3/4] Starting container..."
docker rm -f "${SERVICE_NAME}" 2>/dev/null || true
docker run -d --name "${SERVICE_NAME}" \
    --memory=512m \
    -e SERVICE_NAME="${SERVICE_NAME}" \
    -e SERVICE_PORT="${SERVICE_PORT}" \
    -v "$(pwd)/${JAR}:/service/jar/${SERVICE_NAME}.jar" \
    "${TAG}"

echo ""
echo "[4/4] Waiting for app to start..."
for i in $(seq 1 15); do
    sleep 2
    if docker exec "${SERVICE_NAME}" curl -sf "http://localhost:${SERVICE_PORT}/api/info" > /dev/null 2>&1; then
        echo "============================================"
        echo " App started successfully!"
        echo "============================================"
        docker exec "${SERVICE_NAME}" curl -s "http://localhost:${SERVICE_PORT}/api/info"
        echo ""
        docker exec "${SERVICE_NAME}" curl -s "http://localhost:${SERVICE_PORT}/actuator/health" | python3 -m json.tool 2>/dev/null || docker exec "${SERVICE_NAME}" curl -s "http://localhost:${SERVICE_PORT}/actuator/health"
        echo ""
        echo "--- BUILD & TEST PASSED ---"
        echo ""
        echo "Test: docker logs -f ${SERVICE_NAME}"
        echo "Stop: docker stop ${SERVICE_NAME} && docker rm ${SERVICE_NAME}"
        exit 0
    fi
    echo " Waiting... ($i/15)"
done

echo ""
echo "App failed to start within timeout. Logs:"
docker logs "${SERVICE_NAME}" 2>&1 | tail -40
echo "--- BUILD & TEST FAILED ---"
docker rm -f "${SERVICE_NAME}" 2>/dev/null || true
exit 1
