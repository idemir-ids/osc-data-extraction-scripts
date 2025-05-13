#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation

# OS-Climate / Data Extraction Team

# Script repository/location:
# https://github.com/os-climate/osc-data-extraction-scripts

### Bulk execution script ###

set -o pipefail
# set -vx  # Uncomment to enable verbose output for debugging

### Variables

# Folder location of input PDF files and output files on EFS/NFS mount
SOURCE="inputs"  # Source directory for input files
TARGET="outputs"     # Target directory for output files

# Wildcard that selects the number of files to process
SELECTION="e151f*.pdf"    # File selection pattern, example: "e15*.pdf"

### Functions

# Function to run the OSC pipeline
_run_osc_pipeline() {
    local input_dir="$1"  # Input directory for the pipeline
    local output_dir="$2" # Output directory for the pipeline
    local log_dir="$3"    # Log directory for the pipeline
    
    # Activate the Python virtual environment
    source /osc/venv/bin/activate
    
    # Run the extraction pipeline
    echo "extraction run-local-extraction '$input_dir' --output-folder='$output_dir' --logs-folder='$log_dir' --force"
    osc-transformer-presteps extraction run-local-extraction "$input_dir" --output-folder="$output_dir" --logs-folder="$log_dir" --force
    
    # Deactivate the virtual environment
    deactivate
}

# Export the function for use with parallel
export -f _run_osc_pipeline

# Function to process individual files
_process_files() {
    echo "Processing: $1"
    
    local filename="$1"    # Filename being processed
    local target="$2"      # Target directory for processed files
    local base_filename=$(basename "$filename") # Extract base filename
    
    # Create a unique temporary directory
    local temp_dir=$(mktemp -d)
    
    # Create input, output, and log directories within the temporary directory
    local input_dir="$temp_dir/input"
    local output_dir="$temp_dir/output"
    local log_dir="$temp_dir/log"
    mkdir -p "$input_dir" "$output_dir" "$log_dir"
    
    # Copy the file to the input directory
    cp "$filename" "$input_dir/$base_filename"
    
    # Run the pipeline on the file
    _run_osc_pipeline "$input_dir" "$output_dir" "$log_dir"
    
    # Check if the output directory exists and copy contents to the target directory
    if [ -d "$output_dir" ]; then
        cp "$output_dir/"* "$target"
    else
        echo "Output directory not found."
    fi
    
    # Clean up: remove the temporary directory
    rm -rf "$temp_dir"
}

# Export the function for use with parallel
export -f _process_files

# Determine the number of available processing threads
NPROC_CMD=$(which nproc)
if [ ! -x "$NPROC_CMD" ]; then
    echo "Error: nproc command not found in PATH"
    exit 1
fi
THREADS=$($NPROC_CMD) # Number of threads for parallel processing

# Display script information
echo "OS-Climate / Data Extraction Team"
echo "Bulk execution script"

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

# Setup the Python virtual environment if not already present
if [ ! -d "/osc/venv" ]; then
  echo "Installing required python packages for OSC toolchain"
  apt-get update -qq
  apt-get install -qq python3.12-venv > /dev/null 2>&1
  mkdir -p /osc/venv
  python3 -m venv /osc/venv
  source /osc/venv/bin/activate
  pip3 install osc-transformer-presteps
  deactivate
fi

# Display number of parallel threads
echo "Parallel threads for batch processing: $THREADS"

# Record start time
START=$(date '+%s')

# Display number of input files to process
echo -n "Input files to process: "
FILES=$(ls $SOURCE/$SELECTION) # List files matching the selection pattern
echo "$FILES" | wc -l

# Process files in parallel using the specified number of threads
echo "$FILES" | parallel -j "$THREADS" _process_files {} "$TARGET"

# Record end time and calculate elapsed time
END=$(date '+%s')
ELAPSED=$((END-START))
echo "Elapsed time in seconds: $ELAPSED"

# Indicate completion of batch job
echo "Batch job completed!"