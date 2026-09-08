#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${SIMENV_IMAGE:-simenv:ros1-noetic-cuda128}"
BUILD_VOLUME="${SIMENV_BUILD_VOLUME:-simenv-build}"
DEVEL_VOLUME="${SIMENV_DEVEL_VOLUME:-simenv-devel}"
INSTALL_VOLUME="${SIMENV_INSTALL_VOLUME:-simenv-install}"
COMMAND="${1:-shell}"

usage() {
    cat <<EOF
Usage: $0 {image|shell|build|sim|clean}

  image  Build the ROS1/Noetic + CUDA 12.8 development image.
  shell  Open an interactive ROS1 development shell (default).
  build  Clean the Docker build volumes and run catkin_make.
  sim    Run ./auto.sh (set GUI=false for headless simulation).
  clean  Remove the build/devel/install Docker volumes.

Environment overrides:
  SIMENV_IMAGE, SIMENV_BUILD_VOLUME, SIMENV_DEVEL_VOLUME,
  SIMENV_INSTALL_VOLUME, LIBTORCH_ROOT, TORCH_CUDA_ARCH_LIST,
  CMAKE_CUDA_COMPILER, and the simulation variables documented in
  docs/docker.md.
EOF
}

if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    usage
    exit 0
fi

case "$COMMAND" in
    image)
        exec docker build \
            --build-arg DEV_USER="${USER:-simenv}" \
            --build-arg DEV_UID="$(id -u)" \
            --build-arg DEV_GID="$(id -g)" \
            -t "$IMAGE_NAME" \
            "$ROOT_DIR"
        ;;
    clean)
        for volume_name in "$BUILD_VOLUME" "$DEVEL_VOLUME" "$INSTALL_VOLUME"; do
            if docker volume inspect "$volume_name" >/dev/null 2>&1; then
                docker volume rm "$volume_name"
            else
                echo "Volume $volume_name does not exist; skipping."
            fi
        done
        exit 0
        ;;
    shell|build|sim)
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage >&2
        exit 2
        ;;
esac

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Image $IMAGE_NAME does not exist. Run '$0 image' first." >&2
    exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
    export DISPLAY=:0
fi

XHOST_ENABLED=0
# Only request access to the X server when a GUI was requested.  This keeps
# headless runs usable on CI/SSH hosts that have no X11 server at all.
GUI_REQUESTED=1
case "${GUI:-true}" in
    0|false|FALSE|False|no|NO|off|OFF) GUI_REQUESTED=0 ;;
esac
if command -v xhost >/dev/null 2>&1 && [[ "$COMMAND" != "build" && "$GUI_REQUESTED" == "1" ]]; then
    if xhost +local:docker >/dev/null 2>&1; then
        XHOST_ENABLED=1
    else
        echo "Warning: could not grant X11 access; use GUI=false for headless mode." >&2
    fi
fi
cleanup() {
    if [[ "$XHOST_ENABLED" == "1" ]]; then
        xhost -local:docker >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

DOCKER_ARGS=(
    --rm
    --init
    --gpus all
    --network host
    --shm-size=2g
    --env "DISPLAY=${DISPLAY}"
    --env NVIDIA_VISIBLE_DEVICES=all
    --env NVIDIA_DRIVER_CAPABILITIES=all
    --volume "$ROOT_DIR:/workspace/SimEnv:rw"
    --volume "$BUILD_VOLUME:/workspace/SimEnv/build:rw"
    --volume "$DEVEL_VOLUME:/workspace/SimEnv/devel:rw"
    --volume "$INSTALL_VOLUME:/workspace/SimEnv/install:rw"
)

if [[ "$GUI_REQUESTED" == "1" ]]; then
    DOCKER_ARGS+=(--volume /tmp/.X11-unix:/tmp/.X11-unix:rw)
fi

# Forward configuration overrides to the container. Keeping this as an
# explicit allow-list prevents unrelated host settings from leaking into ROS.
FORWARDED_ENV_NAMES=(
    LIBTORCH_ROOT
    TORCH_CUDA_ARCH_LIST
    CMAKE_CUDA_COMPILER
    GUI
    PAUSED
    AUTO_UNPAUSE
    AUTO_UNPAUSE_DELAY
    START_CONTROLLER
    START_VIRTUAL_JOY
    CONTROLLER_FOREGROUND
    START_BUILDING_CONTROL
    ENABLE_SENSORS
    ENABLE_SENSOR_DATA
    ENABLE_LIVOX
    ENABLE_LIVOX_IMU
    ENABLE_REALSENSE
    ENABLE_DEPTH_CAMERA
    ENABLE_FRONT_CAMERA
    ENABLE_REFEREE_ODOM
    ENABLE_GROUND_TRUTH
    ENABLE_FOOT_CONTACT_SENSOR
    ENABLE_FOOT_FORCE_VISUAL
    ENABLE_JOY_NODE
    ENABLE_POINTCLOUD_CONVERTER
    POINTCLOUD_USE_GROUND_TRUTH_ODOM
    WRITE_GENERATED_TRUTH_COPY
    SEED
    FLOOR_COUNT
    ROOMS_PER_FLOOR
    BUILDING_WIDTH
    BUILDING_LENGTH
    DANGER_COUNT
    DISTRACTOR_COUNT
    UNITREE_CTRL_DT
    UNITREE_LOG_WAIT_WARNINGS
    ROBOT_SPAWN_TIMEOUT
    CONTROLLER_SPAWNER_TIMEOUT
)
for env_name in "${FORWARDED_ENV_NAMES[@]}"; do
    if [[ -n "${!env_name+x}" ]]; then
        DOCKER_ARGS+=(--env "${env_name}=${!env_name}")
    fi
done

if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
    DOCKER_ARGS+=(--env XAUTHORITY=/tmp/.docker.xauthority --volume "$XAUTHORITY:/tmp/.docker.xauthority:ro")
fi

case "$COMMAND" in
    shell)
        docker run -it "${DOCKER_ARGS[@]}" "$IMAGE_NAME" bash
        ;;
    build)
        exec docker run -i "${DOCKER_ARGS[@]}" "$IMAGE_NAME" bash -lc '
            set -e
            # These paths are Docker volume mount points and cannot themselves
            # be removed.  Clear their contents while preserving the mounts.
            for dir in build devel install; do
              mkdir -p "$dir"
              find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
            done
            catkin_make \
              -DCMAKE_BUILD_TYPE=Release \
              -DLIBTORCH_ROOT="${LIBTORCH_ROOT}" \
              -DTORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" \
              -DCMAKE_CUDA_COMPILER="${CMAKE_CUDA_COMPILER}"
        '
        ;;
    sim)
        # Keep an interactive terminal for keyboard control when available,
        # but also allow headless/CI invocation where stdin is not a TTY.
        if [[ -t 0 && -t 1 ]]; then
            docker run -it "${DOCKER_ARGS[@]}" "$IMAGE_NAME" bash -lc 'exec ./auto.sh'
        else
            docker run -i "${DOCKER_ARGS[@]}" "$IMAGE_NAME" bash -lc 'exec ./auto.sh'
        fi
        ;;
esac
