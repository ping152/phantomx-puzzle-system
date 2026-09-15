#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Sending SIGINT so ros_main_controller attempts CM530 STOP..."
docker kill --signal SIGINT phantomx-puzzle-controller >/dev/null 2>&1 || true
sleep 2

cd "${ROOT}"
docker compose -f compose.yaml -f compose.jetson-hardware.yaml --profile hardware down --remove-orphans
echo "Jetson stack stopped. Verify the physical arm is stationary before touching it."

