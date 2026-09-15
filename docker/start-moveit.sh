#!/usr/bin/env bash
set -euo pipefail

exec ros2 launch phantomx_pincher_moveit_config move_group.launch.py \
  ros2_control:=true \
  ros2_control_plugin:=fake \
  ros2_control_command_interface:=position \
  enable_rviz:="${ENABLE_RVIZ:-true}" \
  use_sim_time:=false

