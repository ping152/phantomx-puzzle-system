#!/usr/bin/env bash
set -euo pipefail

cd /opt/puzzle/vision
mode="${VISION_MODE:-mock}"
show_window="${VISION_SHOW_WINDOW:-true}"
pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do
    kill -TERM "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

case "${mode}" in
  mock)
    python3 mock_camera_publisher.py &
    pids+=("$!")
    ;;
  windows)
    python3 windows_stream_bridge_publisher.py --host 0.0.0.0 --port 5001 &
    pids+=("$!")
    ;;
  jetson)
    python3 usb_camera_publisher.py --ros-args -p device_id:="${CAMERA_DEVICE_ID:-0}" &
    pids+=("$!")
    ;;
  *)
    echo "Unsupported VISION_MODE=${mode}" >&2
    exit 2
    ;;
esac

python3 camera_point_cv_subscriber.py --ros-args \
  -p processing_mode:=pick-and-place \
  -p show_window:="${show_window}" \
  -p black_s_max:=255 \
  -p black_v_max:=120 \
  -p black_max_area:=200000.0 &
pids+=("$!")

wait -n
