FROM nvidia/cuda:12.8.1-devel-ubuntu20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DEV_USER=simenv
ARG DEV_UID=1000
ARG DEV_GID=1000
ARG LIBTORCH_URL=https://download.pytorch.org/libtorch/cu128/libtorch-cxx11-abi-shared-with-deps-2.7.1%2Bcu128.zip

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ROS_DISTRO=noetic \
    LIBTORCH_ROOT=/opt/libtorch \
    TORCH_CUDA_ARCH_LIST=12.0 \
    CMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all

# Add the ROS repository before installing ROS Noetic on Ubuntu 20.04.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg2 lsb-release \
    && curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu focal main" \
        > /etc/apt/sources.list.d/ros1.list \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        pkg-config \
        unzip \
        python3 \
        python3-dev \
        python3-numpy \
        python3-pip \
        python3-yaml \
        python3-catkin-tools \
        python3-rosdep \
        python3-rosinstall \
        python3-rosinstall-generator \
        python3-wstool \
        libarmadillo-dev \
        libboost-all-dev \
        libeigen3-dev \
        liblcm-dev \
        libopencv-dev \
        libpcl-dev \
        libprotobuf-dev \
        protobuf-compiler \
        libgazebo11-dev \
        ros-noetic-desktop-full \
        ros-noetic-catkin \
        ros-noetic-cmake-modules \
        ros-noetic-cv-bridge \
        ros-noetic-dynamic-reconfigure \
        ros-noetic-gazebo-ros-pkgs \
        ros-noetic-image-transport \
        ros-noetic-joy \
        ros-noetic-laser-geometry \
        ros-noetic-navigation \
        ros-noetic-pcl-ros \
        ros-noetic-ros-control \
        ros-noetic-ros-controllers \
        ros-noetic-tf2-eigen \
        ros-noetic-xacro \
    && rm -rf /var/lib/apt/lists/*

# Download the CUDA 12.8 C++ distribution used by junior_ctrl. Keeping this in
# the image makes a fresh container independent of the host's Python torch.
RUN mkdir -p /opt \
    && curl -fL --retry 5 --retry-delay 2 "${LIBTORCH_URL}" -o /tmp/libtorch.zip \
    && unzip -q /tmp/libtorch.zip -d /tmp \
    && mv /tmp/libtorch /opt/libtorch \
    && rm -f /tmp/libtorch.zip \
    && test -f /opt/libtorch/share/cmake/Torch/TorchConfig.cmake

RUN groupadd --gid "${DEV_GID}" "${DEV_USER}" \
    && useradd --uid "${DEV_UID}" --gid "${DEV_GID}" --create-home --shell /bin/bash "${DEV_USER}" \
    && mkdir -p /workspace/SimEnv /workspace/SimEnv/build /workspace/SimEnv/devel /workspace/SimEnv/install \
    && chown -R "${DEV_UID}:${DEV_GID}" /workspace /home/"${DEV_USER}"

RUN rosdep init 2>/dev/null || true \
    && printf '%s\n' \
        'source /opt/ros/noetic/setup.bash' \
        'export LIBTORCH_ROOT="${LIBTORCH_ROOT:-/opt/libtorch}"' \
        'export LD_LIBRARY_PATH="${LIBTORCH_ROOT}/lib:/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"' \
        '[ -f /workspace/SimEnv/devel/setup.bash ] && source /workspace/SimEnv/devel/setup.bash' \
        > /etc/profile.d/simenv.sh \
    && chown "${DEV_UID}:${DEV_GID}" /etc/profile.d/simenv.sh

COPY docker/entrypoint.sh /usr/local/bin/simenv-entrypoint
RUN chmod 755 /usr/local/bin/simenv-entrypoint

WORKDIR /workspace/SimEnv
USER "${DEV_USER}"
ENTRYPOINT ["/usr/local/bin/simenv-entrypoint"]
CMD ["bash"]
