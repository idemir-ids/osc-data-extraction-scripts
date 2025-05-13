#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation

# OS-Climate / Data Extraction Team
# Script repository/location:
# https://github.com/os-climate/osc-data-extraction-scripts

### Web server setup script ###

# Configuration file for Lighttpd
LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"

# Directory where the web server serves files
SERVER_DIR="/var/www/html"

# Directory for data extraction operations
DATA_EXTRACTION_DIR="/data-extraction"

# Exit immediately if any command fails and enable pipefail
set -e
set -o pipefail

# Update package lists quietly
echo "Updating package lists..."
apt-get update -qq

# Install Lighttpd quietly, suppressing output
echo "Installing Lighttpd..."
apt-get install -qq lighttpd > /dev/null 2>&1

# Enable directory listing in Lighttpd configuration
echo "Configuring Lighttpd"
echo 'server.modules += ( "mod_dirlisting" )' >> "$LIGHTTPD_CONF"
echo 'dir-listing.activate = "enable"' >> "$LIGHTTPD_CONF"

# Remove any existing files in the server directory
rm -f "$SERVER_DIR"/*

# Create directories for storing input and output files
echo "Create directories for storing input and output files"
mkdir -p "$DATA_EXTRACTION_DIR/inputs_www"
mkdir -p "$DATA_EXTRACTION_DIR/outputs_www"

# Set permissions to allow read and execute access
chmod -R 755 "$DATA_EXTRACTION_DIR/inputs_www"
chmod -R 755 "$DATA_EXTRACTION_DIR/outputs_www"

# Create symbolic links to the input and output directories in the server directory
ln -s "$DATA_EXTRACTION_DIR/inputs_www" "$SERVER_DIR/inputs_www"
ln -s "$DATA_EXTRACTION_DIR/outputs_www" "$SERVER_DIR/outputs_www"

# Restart Lighttpd service to apply configuration changes
service lighttpd restart

# Print success message
echo "Lighttpd is installed and configured to serve $SERVE_DIR with directory listing enabled."