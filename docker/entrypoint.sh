#!/usr/bin/env bash
set -eo pipefail

# Some ROS Noetic profile snippets reference optional variables (for example
# ROS_MASTER_URI) while the shell is being initialized.  Source ROS with nounset
# temporarily disabled, then restore strict handling for the rest of the
# entrypoint.
set +u
source /opt/ros/noetic/setup.bash
set -u
export LIBTORCH_ROOT="${LIBTORCH_ROOT:-/opt/libtorch}"
export CMAKE_CUDA_COMPILER="${CMAKE_CUDA_COMPILER:-/usr/local/cuda/bin/nvcc}"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-12.0}"
export LD_LIBRARY_PATH="${LIBTORCH_ROOT}/lib:/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

if [[ -f /workspace/SimEnv/devel/setup.bash ]]; then
    source /workspace/SimEnv/devel/setup.bash
fi

export ROS_PACKAGE_PATH="/workspace/SimEnv/src${ROS_PACKAGE_PATH:+:${ROS_PACKAGE_PATH}}"
export PYTHONPATH="/workspace/SimEnv/src/building_generator_classic:/workspace/SimEnv/src/building_generator_core${PYTHONPATH:+:${PYTHONPATH}}"
cd /workspace/SimEnv

exec "$@"
