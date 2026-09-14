#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=================================================="
echo "Phase 2: Purging Default Packages & Building Drivers"
echo "=================================================="

# 1. Purge upstream/conflicting packages
sudo apt remove --purge -y libcamera-dev libcamera0* rpicam-apps libcamera-tools
sudo apt autoremove -y

# 2. Install all build dependencies (including Boost & FFmpeg/Libav for H.264)
sudo apt update
sudo apt install -y build-essential git meson cmake ninja-build \
  python3-pip python3-jinja2 python3-yaml python3-ply pybind11-dev \
  libboost-dev libboost-program-options-dev libboost-system-dev \
  libgnutls28-dev openssl libtiff-dev libdrm-dev libglib2.0-dev \
  libgstreamer-plugins-base1.0-dev libexif-dev libepoxy-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev ffmpeg

# 3. Build and install Raspberry Pi libcamera fork with PiSP support
cd ~
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
cd ~
if [ -d "rpicam-apps" ]; then rm -rf rpicam-apps; fi
git clone https://github.com/raspberrypi/rpicam-apps.git
cd rpicam-apps

meson setup build --buildtype=release -Denable_qt=disabled -Denable_libav=enabled
ninja -C build
sudo ninja -C build install
sudo ldconfig

echo "=================================================="
echo "Phase 3 & 4: Workspace Setup & ROS 2 Node Creation"
echo "=================================================="

# 5. Clean up workspace and source directory
mkdir -p ~/ros2_ws/src
if [ -d "~/ros2_ws/src/rpicam-apps" ]; then
    rm -rf ~/ros2_ws/src/rpicam-apps
fi

# 6. Clone camera_ros into ROS 2 workspace
cd ~/ros2_ws/src
if [ -d "camera_ros" ]; then rm -rf camera_ros; fi
git clone https://github.com/christianrauch/camera_ros.git

# 7. Install ROS 2 dependencies (Skipping upstream libcamera)
cd ~/ros2_ws
source /opt/ros/jazzy/setup.bash || source /opt/ros/humble/setup.bash
rosdep update
rosdep install --from-paths src --ignore-src -y --skip-keys=libcamera

# 8. Build camera_ros node
colcon build --packages-select camera_ros
source install/setup.bash

echo "=================================================="
echo "SETUP COMPLETE!"
echo "Run 'rpicam-hello --list-cameras' to test hardware."
echo "Run 'ros2 run camera_ros camera_node --ros-args -r /camera/image:=/camera/image_raw' to publish topics."
echo "=================================================="
