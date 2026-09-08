# Docker 开发环境

本仓库提供一个纯 Docker 的单容器 ROS1 开发环境，不使用 Docker Compose。容器基于 CUDA 12.8、Ubuntu 20.04 和 ROS Noetic，源码从宿主机挂载，构建产物使用独立 Docker volume。
镜像默认进入开发 shell，不会在启动容器时自动运行仿真。

## 宿主机要求

- x86_64 Linux
- Docker Engine
- NVIDIA Container Toolkit
- NVIDIA 驱动支持 CUDA 12.8
- 使用 Gazebo GUI 时，需要 X11；Wayland 通常需要 XWayland

检查 GPU 容器运行时：

```bash
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu20.04 nvidia-smi
```

## 构建镜像

首次构建会下载约 3.8 GB 的 CUDA 12.8 版 libtorch，镜像也会比较大：

```bash
./docker-run.sh image
```

脚本会把镜像内的开发用户 UID/GID 设置为当前宿主用户，避免挂载源码后产生 root 文件。

## 编译和运行

在隔离的 `simenv-build`、`simenv-devel`、`simenv-install` volumes 中进行干净编译：

```bash
./docker-run.sh build
```

进入交互式 ROS1 shell：

```bash
./docker-run.sh shell
```

启动 Gazebo GUI 和比赛环境：

```bash
./docker-run.sh sim
```

无 GUI 启动：

```bash
GUI=false ./docker-run.sh sim
```

源码修改会立即反映到容器内。`build` 命令会清理并重新生成隔离 volume 中的 `build/devel/install`，宿主仓库原有的旧构建目录不会被使用。

清理构建 volumes：

```bash
./docker-run.sh clean
```

## CUDA 和 libtorch

镜像内路径如下：

```text
/usr/local/cuda
/opt/libtorch
```

项目 CMake 默认使用 `LIBTORCH_ROOT=/opt/libtorch`、`CMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc` 和 `TORCH_CUDA_ARCH_LIST=12.0`。可以在运行容器时覆盖，例如：

```bash
TORCH_CUDA_ARCH_LIST=8.6 ./docker-run.sh build
```

## GUI 排查

`docker-run.sh shell` 和 `docker-run.sh sim` 会临时执行 `xhost +local:docker`，退出后自动撤销。如果 Gazebo 无法打开窗口，可以先验证：

```bash
echo "$DISPLAY"
xhost
```

远程服务器或没有 X11 时使用 `GUI=false`。ROS、Gazebo、控制器和比赛场景都在同一个容器中运行；宿主机 ROS2 环境不会被修改。
