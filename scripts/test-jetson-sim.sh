#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOCKER_PLATFORM=linux/arm64
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-32}"
export VISION_MODE=mock
export ENABLE_RVIZ="${ENABLE_RVIZ:-true}"

python3 "${ROOT}/scripts/deployment_guard.py" --require-jetson
docker info >/dev/null

cd "${ROOT}"
cleanup() {
  docker compose --profile test down --remove-orphans || true
}
trap cleanup EXIT

docker compose --profile test build
for image in \
  "${MOTION_IMAGE:-ghcr.io/ping152/phantomx-puzzle-motion:v0.1.0-rc1}" \
  "${VISION_IMAGE:-ghcr.io/ping152/phantomx-puzzle-vision:v0.1.0-rc1}"; do
  architecture="$(docker image inspect "${image}" --format '{{.Architecture}}')"
  [[ "${architecture}" == "arm64" ]] || {
    echo "Image is not linux/arm64: ${image} (${architecture})" >&2
    exit 2
  }
done
docker compose --profile test run --rm controller-tests
docker compose --profile test up -d moveit
docker compose --profile test run --rm multipoint-probe

echo "Jetson ARM64 simulation verification passed. No hardware was driven."
