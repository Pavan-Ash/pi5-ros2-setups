#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=================================================="
echo "Phase 1: Setting Environment for ROS 2 Jazzy"
echo "=================================================="

# Force ROS_DISTRO to jazzy
export ROS_DISTRO=jazzy

# Source ROS 2 Jazzy setup
if [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
else
    echo "ERROR: ROS 2 Jazzy installation not found at /opt/ros/jazzy/setup.bash"
    exit 1
fi

echo "=================================================="
echo "Phase 2: Purging Default Packages & Building Drivers"
echo "=================================================="

# 1. Purge upstream/conflicting packages
sudo apt remove --purge -y libcamera-dev libcamera0* rpicam-apps libcamera-tools || true
sudo apt autoremove -y

# 2. Install build dependencies and ROS 2 Jazzy perception packages
sudo apt update
sudo apt install -y build-essential git meson cmake ninja-build \
  python3-pip python3-jinja2 python3-yaml python3-ply pybind11-dev \
  libboost-dev libboost-program-options-dev libboost-system-dev \
  libgnutls28-dev openssl libtiff-dev libdrm-dev libglib2.0-dev \
  libgstreamer-plugins-base1.0-dev libexif-dev libepoxy-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev ffmpeg \
  ros-jazzy-cv-bridge ros-jazzy-image-transport \
  ros-jazzy-camera-info-manager

# Configure library loader paths for custom compiled shared libraries
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/usr-local.conf
if [ -d "/usr/local/lib/aarch64-linux-gnu" ]; then
  echo "/usr/local/lib/aarch64-linux-gnu" | sudo tee -a /etc/ld.so.conf.d/usr-local.conf
fi

# 3. Build and install Raspberry Pi libcamera fork with VC4 (Pi 3/4) & PiSP (Pi 5) support
cd "$HOME"
if [ -d "libcamera" ]; then rm -rf libcamera; fi
git clone https://github.com/raspberrypi/libcamera.git
cd libcamera

meson setup build --buildtype=release \
  -Dpipelines=rpi/vc4,rpi/pisp \
  -Dipas=rpi/vc4,rpi/pisp \
  -Dv4l2=true \
  -Dgstreamer=enabled \
  -Dtest=false \
  -Dlc-compliance=disabled \
  -Dcam=disabled \
  -Dqcam=disabled

ninja -C build
sudo ninja -C build install
sudo ldconfig

# 4. Build and install rpicam-apps with libav enabled
cd "$HOME"
if [ -d "rpicam-apps" ]; then rm -rf rpicam-apps; fi
git clone https://github.com/raspberrypi/rpicam-apps.git
cd rpicam-apps

meson setup build --buildtype=release -Denable_qt=disabled -Denable_libav=enabled
ninja -C build
sudo ninja -C build install
sudo ldconfig

echo "=================================================="
echo "Phase 3 & 4: Workspace Setup & ROS 2 Jazzy Node Build"
echo "=================================================="

# 5. Clean up workspace and source directory
mkdir -p "$HOME/ros2_ws/src"
if [ -d "$HOME/ros2_ws/src/rpicam-apps" ]; then
    rm -rf "$HOME/ros2_ws/src/rpicam-apps"
fi

# 6. Clone camera_ros into ROS 2 workspace
cd "$HOME/ros2_ws/src"
if [ -d "camera_ros" ]; then rm -rf camera_ros; fi
git clone https://github.com/christianrauch/camera_ros.git

# 7. Install remaining dependencies via rosdep (Skipping system libcamera)
cd "$HOME/ros2_ws"
rosdep update
rosdep install --from-paths src --ignore-src -y --skip-keys="libcamera libcamera-dev"

# 8. Build camera_ros node using colcon
colcon build --packages-select camera_ros
source install/setup.bash

echo "=================================================="
echo "SETUP COMPLETE FOR ROS 2 JAZZY!"
echo "1. Run 'rpicam-hello --list-cameras' to verify hardware detection."
echo "2. Run 'ros2 run camera_ros camera_node --ros-args -r /camera/image:=/camera/image_raw' to test streaming."
echo "=================================================="
