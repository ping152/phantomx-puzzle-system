#!/usr/bin/env bash
set -euo pipefail

set +u
source "/opt/ros/${ROS_DISTRO:-humble}/setup.bash"
if [[ -f /opt/puzzle/ws/install/setup.bash ]]; then
  source /opt/puzzle/ws/install/setup.bash
fi
set -u

exec "$@"

