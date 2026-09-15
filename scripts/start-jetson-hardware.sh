#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  while IFS='=' read -r key value; do
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ -z "${!key+x}" ]]; then
      export "${key}=${value}"
    fi
  done < "${ROOT}/.env"
fi
serial_device="${CM530_DEVICE:-/dev/phantomx-cm530}"
camera_device="${CAMERA_DEVICE:-/dev/video0}"

python3 "${ROOT}/scripts/deployment_guard.py" --require-jetson --expect-owner jetson --owner "${HARDWARE_OWNER:-}"
if [[ "${RELEASE_MODE:-0}" == "1" ]]; then
  python3 "${ROOT}/scripts/deployment_guard.py" \
    --release-image "${MOTION_IMAGE:-}" --release-image "${VISION_IMAGE:-}"
fi

[[ "${serial_device}" =~ ^/dev/(ttyUSB[0-9]+|ttyACM[0-9]+|phantomx-cm530)$ ]] || {
  echo "Unsupported serial path: ${serial_device}" >&2
  exit 2
}
[[ -c "${serial_device}" ]] || { echo "CM530 serial missing: ${serial_device}" >&2; exit 2; }
[[ -c "${camera_device}" ]] || { echo "Camera missing: ${camera_device}" >&2; exit 2; }
if command -v fuser >/dev/null 2>&1 && fuser "${serial_device}" >/dev/null 2>&1; then
  echo "CM530 serial is already in use: ${serial_device}" >&2
  exit 2
fi

export DOCKER_PLATFORM=linux/arm64
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-32}"
export VISION_MODE=jetson
export CM530_DEVICE="${serial_device}"
export CM530_CONTAINER_DEVICE="${serial_device}"
export CAMERA_DEVICE="${camera_device}"
export CAMERA_DEVICE_ID="${CAMERA_DEVICE_ID:-0}"

read -r -p "Clear the arm workspace, make emergency STOP reachable, then type HOME to authorize homing: " confirmation
[[ "${confirmation}" == "HOME" ]] || { echo "HOME authorization not granted." >&2; exit 2; }

cd "${ROOT}"
cleanup() {
  "${ROOT}/scripts/stop-jetson.sh" || true
}
trap cleanup EXIT INT TERM

docker compose -f compose.yaml -f compose.jetson-hardware.yaml --profile hardware up -d moveit vision
nodes="$(docker compose -f compose.yaml -f compose.jetson-hardware.yaml exec -T moveit bash -lc 'ros2 node list' 2>/dev/null || true)"
if grep -q '^/ros_main_controller$' <<<"${nodes}"; then
  echo "A ros_main_controller already exists in ROS_DOMAIN_ID=${ROS_DOMAIN_ID}." >&2
  exit 2
fi

echo "Controller is interactive. Press R to plan and move; press Ctrl+C for STOP and shutdown."
docker compose -f compose.yaml -f compose.jetson-hardware.yaml --profile hardware \
  run --name phantomx-puzzle-controller --rm controller
