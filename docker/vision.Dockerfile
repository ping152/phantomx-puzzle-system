ARG ROS_DISTRO=humble
FROM ros:${ROS_DISTRO}-ros-base

ARG ROS_DISTRO
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    ROS_DISTRO=${ROS_DISTRO} \
    PYTHONUNBUFFERED=1
SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-colcon-common-extensions \
    python3-numpy \
    python3-opencv \
    ros-${ROS_DISTRO}-cv-bridge \
    ros-${ROS_DISTRO}-tf2-geometry-msgs \
    ros-${ROS_DISTRO}-tf2-ros \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/puzzle/ws
COPY components/vision/opencv_ros2_bridge_interfaces ./src/opencv_ros2_bridge_interfaces
RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon build --merge-install --packages-select opencv_ros2_bridge_interfaces

COPY components/vision /opt/puzzle/vision
COPY docker/ros-entrypoint.sh docker/start-vision.sh /opt/puzzle/bin/
RUN chmod +x /opt/puzzle/bin/*.sh \
    && printf '%s\n' "${TARGETARCH}" > /opt/puzzle/image-architecture

WORKDIR /opt/puzzle/vision
ENTRYPOINT ["/opt/puzzle/bin/ros-entrypoint.sh"]
CMD ["/opt/puzzle/bin/start-vision.sh"]

