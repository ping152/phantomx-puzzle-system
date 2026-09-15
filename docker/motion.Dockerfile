ARG ROS_DISTRO=humble
FROM ros:${ROS_DISTRO}-ros-base

ARG ROS_DISTRO
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    ROS_DISTRO=${ROS_DISTRO} \
    PYTHONUNBUFFERED=1
SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    fastdds-tools \
    python3-colcon-common-extensions \
    python3-pip \
    python3-serial \
    ros-${ROS_DISTRO}-control-msgs \
    ros-${ROS_DISTRO}-joint-state-broadcaster \
    ros-${ROS_DISTRO}-joint-trajectory-controller \
    ros-${ROS_DISTRO}-moveit \
    ros-${ROS_DISTRO}-robot-state-publisher \
    ros-${ROS_DISTRO}-ros2-control \
    ros-${ROS_DISTRO}-ros2-controllers \
    ros-${ROS_DISTRO}-rviz2 \
    ros-${ROS_DISTRO}-xacro \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/puzzle/ws
COPY components/phantomx_pincher/phantomx_pincher ./src/phantomx_pincher
COPY components/phantomx_pincher/phantomx_pincher_description ./src/phantomx_pincher_description
COPY components/phantomx_pincher/phantomx_pincher_moveit_config ./src/phantomx_pincher_moveit_config
COPY components/vision/opencv_ros2_bridge_interfaces ./src/opencv_ros2_bridge_interfaces
COPY components/controller ./src/ros2_main_control

RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release \
       --packages-select opencv_ros2_bridge_interfaces phantomx_pincher_description \
       phantomx_pincher_moveit_config phantomx_pincher ros2_main_control

COPY docker/ros-entrypoint.sh docker/start-moveit.sh docker/start-controller.sh /opt/puzzle/bin/
RUN chmod +x /opt/puzzle/bin/*.sh \
    && printf '%s\n' "${TARGETARCH}" > /opt/puzzle/image-architecture

ENTRYPOINT ["/opt/puzzle/bin/ros-entrypoint.sh"]
CMD ["/opt/puzzle/bin/start-moveit.sh"]
