#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Starting ROS 2 Jazzy Installation (Laptop / Intel/AMD x86_64) ==="

# 1. Set up locale
echo "--> Setting up locale..."
sudo apt update
sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# 2. Add the ROS 2 repository
echo "--> Adding ROS 2 repository..."
sudo apt install -y software-properties-common curl
sudo add-apt-repository -y universe
sudo apt update

sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu \
$(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
| sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# 3. System Upgrade & ROS 2 Package Installation
echo "--> Performing full upgrade and installing ROS 2 Jazzy Base & dev tools..."
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y bzip2 ros-jazzy-ros-base ros-dev-tools ros-jazzy-demo-nodes-py

# 4. Environment Configuration
echo "--> Sourcing ROS 2 environment in ~/.bashrc..."
if ! grep -q "source /opt/ros/jazzy/setup.bash" ~/.bashrc; then
  echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
fi

# 5. Initialize rosdep
echo "--> Initializing rosdep..."
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi
rosdep update || true

# 6. Create Workspace
echo "--> Creating ROS 2 workspace..."
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws

echo "=== Installation & Workspace Setup Complete! ==="
