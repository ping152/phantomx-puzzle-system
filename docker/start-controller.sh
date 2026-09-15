#!/usr/bin/env bash
set -euo pipefail

exec ros2 run ros2_main_control ros_main_controller --ros-args \
  -p serial_port:="${CM530_CONTAINER_DEVICE:-/dev/ttyUSB0}" \
  -p baudrate:=57600 \
  -p rviz_sync_enabled:="${RVIZ_SYNC_ENABLED:-true}" \
  -p target_z_offset_m:=0.05 \
  -p pickup_z_m:=0.02 \
  -p min_target_z_m:=0.02

