#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation

# OS-Climate / Data Extraction Team

# Script repository/location:
# https://github.com/os-climate/osc-data-extraction-scripts

### Installation script ###

set -o pipefail
# set -vx  # Uncomment to enable verbose output for debugging


# Display script information
echo "OS-Climate / Data Extraction Team"
echo "Installation script"

# Set timezone if not already set
if [ ! -s /etc/localtime ]; then
  echo "Setting timezone"
  ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime
fi

# Install GNU parallel if not already installed
if ! (which parallel > /dev/null 2>&1); then
  echo "Installing GNU parallel"
  apt-get update -qq
  apt-get install -qq parallel > /dev/null 2>&1
fi

# Setup osc-transformer-presteps
if [ ! -d "/data-extraction/venv_presteps" ]; then
  echo "Installing osc-transformer-presteps"
  apt-get update -qq
  apt-get install -qq python3.12-venv > /dev/null 2>&1
  mkdir -p /data-extraction/venv_presteps
  python3.12 -m venv /data-extraction/venv_presteps
  source /data-extraction/venv_presteps/bin/activate
  pip install osc-transformer-presteps  > /dev/null 2>&1
  deactivate
fi

# Setup osc-rule-based-extractor
if [ ! -d "/data-extraction/venv_rb" ]; then
  echo "Installing osc-rule-based-extractor"
  CURDIR=$(pwd)
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata  > /dev/null 2>&1
  apt-get install -qq git  > /dev/null 2>&1
  apt-get install -qq python3.12-venv > /dev/null 2>&1
  mkdir -p /data-extraction
  cd /data-extraction
  git clone --quiet https://github.com/idemir-ids/osc-xpdf-mod
  git clone --quiet https://github.com/idemir-ids/osc-rule-based-extractor
  mkdir -p /data-extraction/venv_rb
  python3.12 -m venv /data-extraction/venv_rb
  apt-get install -qq software-properties-common  > /dev/null 2>&1
  apt-get install -qq wget gfortran libopenblas-dev liblapack-dev libpng-dev libfreetype-dev libfontconfig  > /dev/null 2>&1
  wget -q http://ppa.launchpad.net/linuxuprising/libpng12/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1+1~ppa0~eoan_amd64.deb
  dpkg -i /data-extraction/libpng12-0_1.2.54-1ubuntu1.1+1~ppa0~eoan_amd64.deb > /dev/null 2>&1
  #dpkg -i /data-extraction/osc-rule-based-extractor/res/libpng12-0_1.2.54-1ubuntu1.1+1_ppa0_eoan_amd64.deb > /dev/null 2>&1
  chmod +x /data-extraction/osc-xpdf-mod/bin/pdftohtml_mod
  source /data-extraction/venv_rb/bin/activate
  cd /data-extraction/osc-rule-based-extractor
  pip install pdm  > /dev/null 2>&1
  pdm sync -q
  deactivate
  cd "$CURDIR"
fi

if [ ! -d "/data-extraction/venv_tb" ]; then
  echo "Installing osc-transformer-based-extractor"
  CURDIR=$(pwd)
  apt-get update -qq
  apt-get install -qq git
  apt-get install -qq python3.12-venv > /dev/null 2>&1
  mkdir -p /data-extraction/venv_tb
  
  #### Auto install from PyPy, not currently used:
  #python3.12 -m venv /data-extraction/venv_tb
  #source /data-extraction/venv_tb/bin/activate
  # pip install osc-transformer-based-extractor  > /dev/null 2>&1 ##not currently used
  
  #### Manual install from github:
  cd /data-extraction
  git clone --quiet https://github.com/idemir-ids/osc-transformer-based-extractor
  python3.12 -m venv /data-extraction/venv_tb
  source /data-extraction/venv_tb/bin/activate
  cd /data-extraction/osc-transformer-based-extractor/
  pip install pdm > /dev/null 2>&1
  pdm lock -q
  pdm sync -q
  deactivate
  cd "$CURDIR"
fi