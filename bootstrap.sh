#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation

# Repository location to update/refresh scripts
CLONE_HTTPS="https://github.com/idemir-ids/osc-data-extraction-scripts.git"

SUDO_CMD=$(which sudo)
WHOAMI=$(whoami)
if [ ! -x "$SUDO_CMD" ] || [ "$WHOAMI" = "root" ]; then
    SUDO_CMD=""
fi

if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  source /etc/os-release
fi

_install_docker() {

echo "Installing Docker"

# shellcheck disable=SC2031
if [ "$NAME" = "Debian" ] || [ "$NAME" = "Debian GNU/Linux" ]; then
  $SUDO_CMD apt-get -qq remove docker.io docker-doc docker-compose podman-docker containerd runc
  $SUDO_CMD apt-get -qq update
  $SUDO_CMD apt-get -qq install ca-certificates curl
  $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
  $SUDO_CMD curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  $SUDO_CMD chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  $SUDO_CMD echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  $SUDO_CMD tee /etc/apt/sources.list.d/docker.list > /dev/null
  $SUDO_CMD apt-get -qq update
  $SUDO_CMD apt-get -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO_CMD apt-get install -qq wget vim less git nfs-common

elif [ "$NAME" = "Ubuntu" ]; then
  $SUDO_CMD apt-get -qq remove docker.io docker-doc docker-compose podman-docker containerd runc
  $SUDO_CMD apt-get -qq update
  $SUDO_CMD apt-get -qq install ca-certificates curl
  $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
  $SUDO_CMD curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  $SUDO_CMD echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  $SUDO_CMD apt-get update
  $SUDO_CMD apt-get install -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO_CMD apt-get install -qq wget vim less git nfs-common

elif [ "$NAME" = "Fedora" ] || [ "$NAME" = "Fedora Linux" ]; then
  $SUDO_CMD dnf -y install dnf-plugins-core
  $SUDO_CMD dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  $SUDO_CMD dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO_CMD dnf install -y wget curl vim less git nfs-utils

elif [ "$NAME" = "Amazon Linux" ]; then
  $SUDO_CMD yum update -y
  $SUDO_CMD yum install -y docker
  $SUDO_CMD usermod -a -G docker ec2-user
  $SUDO_CMD yum install -y wget vim less git nfs-utils amazon-efs-utils
else
  echo "Unsupported distribution"
  echo "Supported distributions: Ubuntu|Debian|Fedora|AmazonLinux"
  exit 1
fi

if [ -S /var/run/docker.sock ]; then
  echo "Setting: setfacl -m user:$USER:rw /var/run/docker.sock"
  $SUDO_CMD setfacl -m "user:$USER:rw" /var/run/docker.sock
fi
}

# Install/run Docker
DOCKER_CMD=$(which docker 2>&1)
if [ ! -x "$DOCKER_CMD" ]; then
  _install_docker
fi
# Start at boot and run Docker
$SUDO_CMD systemctl enable docker
$SUDO_CMD systemctl start docker
if ! ($SUDO_CMD docker version > /dev/null 2>&1); then
  echo "Error: Docker failed to install/start"
  echo "Supported distributions: Ubuntu|Debian|Fedora|AmazonLinux"
  exit 1
fi

if [ -S /var/run/docker.sock ]; then
  $SUDO_CMD setfacl -m "user:$USER:rw" /var/run/docker.sock
fi

if [ ! -d /osc ]; then
  echo "Creating directory: /osc"
  $SUDO_CMD mkdir /osc
fi

echo "Taking backup of /etc/fstab"
$SUDO_CMD cp /etc/fstab /etc/fstab.backup
if ! ($SUDO_CMD grep -q '/osc' /etc/fstab);
then
  echo "Creating /etc/fstab entry for NFS mount"
  $SUDO_CMD cp /etc/fstab /tmp/fstab
  $SUDO_CMD chmod a+w /tmp/fstab
  echo "fs-0abca58dcce09a51a.efs.eu-west-2.amazonaws.com:/                        /osc         nfs4   defaults,noatime  0   0" >> /tmp/fstab
  $SUDO_CMD mv /tmp/fstab /etc/fstab
  $SUDO_CMD chmod og-w /etc/fstab
fi

if [ ! -d /osc/data-extraction ]; then
  echo "Mounting EFS/NFS mount"
  $SUDO_CMD systemctl daemon-reload
  $SUDO_CMD mount /osc
fi

# Navigate to EFS/NFS mount location
if [ -d /osc/data-extraction ]; then
  cd /osc/data-extraction || exit
else
  echo "NFS mount unavailable"; exit 1
fi

# Always get fresh copy from github
$SUDO_CMD rm -rf /osc/data-extraction/osc-data-extraction-scripts
echo "Updating scripts from repository:"
echo "$CLONE_HTTPS"
$SUDO_CMD git clone --quiet "$CLONE_HTTPS"

if [ ! -f script.sh ]; then
  echo "Creating symlink for: script.sh"
  $SUDO_CMD ln -s osc-data-extraction-scripts/script.sh script.sh
fi

if [ ! -f websrv.sh ]; then
  echo "Creating symlink for: websrv.sh"
  $SUDO_CMD ln -s osc-data-extraction-scripts/websrv.sh websrv.sh
fi

CURRENT_DIR=$(pwd)
BASE_DIR=$(basename "$CURRENT_DIR")
if [ "$BASE_DIR" = "data-extraction" ]; then
  echo "Starting Ubuntu Docker container..."
  # By default starts an interactive shell inside container
  docker run -v "$PWD":/data-extraction -ti -p 80:80 ubuntu:24.04 /bin/bash
  # Non-interactive goes directly to data processing
  # docker run -v "$PWD":/data-extraction -ti ubuntu:22.04 /bin/bash /data-extraction/script.sh
else
    echo "Error: invoke the script from mounted data-extraction folder"; exit 1
fi

echo "Container and batch job stopped running"; exit 0
