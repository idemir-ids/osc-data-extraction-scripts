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
    local input_dir="$1"      # Input directory for the pipeline
    local output_dir="$2"     # Output directory for the pipeline
    local log_dir="$3"        # Log directory for the pipeline
    local rb_work_dir="$4"    # Work directory for rule-based extraction
    
    
    ##### OSC Transformer Presteps ###
    echo "OSC Transformer Presteps" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_presteps/bin/activate
    
    # Run the osc-transformer-presteps ( TODO : Very slow for e15dc57a77884d11a9d0d19116e4800d.pdf )
    echo "extraction run-local-extraction '$input_dir' --output-folder='$output_dir' --logs-folder='$log_dir' --force"
    osc-transformer-presteps extraction run-local-extraction "$input_dir" --output-folder="$output_dir" --logs-folder="$log_dir" --force
    
    # Deactivate the virtual environment
    deactivate
    
    
    ##### OSC Rule-based KPI Extraction ###
    echo "OSC Rule-based KPI Extraction" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_rb/bin/activate
    
    # Run the rule-based-extractor
    echo "osc-rule-based-extractor --pdftohtml_mod_executable /data-extraction/data-extraction-xpdf-mod/bin/pdftohtml_mod --raw_pdf_folder '$input_dir' --working_folder '$rb_work_dir' --output_folder '$output_dir' --verbosity 0 > '$log_dir/rb.log' 2>/dev/null"
    osc-rule-based-extractor --pdftohtml_mod_executable /data-extraction/data-extraction-xpdf-mod/bin/pdftohtml_mod --raw_pdf_folder "$input_dir" --working_folder "$rb_work_dir" --output_folder "$output_dir" --verbosity 0 > "$log_dir/rb.log" 2>/dev/null
    
    # Deactivate the virtual environment
    deactivate


    ##### OSC Transformer-based KPI Extraction ###
    echo "OSC Transformer-based KPI Extraction" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_tb/bin/activate
    
    # Run the transformer-based-extractor
    
    
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
    local rb_work_dir="$temp_dir/rb_work"
    mkdir -p "$input_dir" "$output_dir" "$log_dir" "$rb_work_dir"
    
    # Copy the file to the input directory
    cp "$filename" "$input_dir/$base_filename"
    
    # Run the pipeline on the file
    _run_osc_pipeline "$input_dir" "$output_dir" "$log_dir" "$rb_work_dir"
    
    # Check if the output directory exists and copy contents to the target directory
    if [ -d "$output_dir" ]; then
        cp "$output_dir/"* "$target"
    else
        echo "Output directory not found."
    fi
    
    # Clean up: remove the temporary directory
    #rm -rf "$temp_dir"
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
  git clone https://github.com/idemir-ids/osc-transformer-based-extractor
  python3.12 -m venv /data-extraction/venv_tb
  source /data-extraction/venv_tb/bin/activate
  cd /data-extraction/osc-transformer-based-extractor/
  pip install pdm > /dev/null 2>&1
  pdm lock -q
  pdm sync -q
  deactivate
  cd "$CURDIR"
fi


# Display number of parallel threads
echo "Parallel threads for batch processing: $THREADS"

# Record start time
START=$(date '+%s')

# Display number of input files to process
echo -n "Input files to process: "
find "$SOURCE" -type f -name "$SELECTION" | wc -l

# Process files in parallel using the specified number of threads
find "$SOURCE" -type f -name "$SELECTION" | parallel -j "$THREADS" _process_files {} "$TARGET"

# Record end time and calculate elapsed time
END=$(date '+%s')
ELAPSED=$((END-START))
echo "Elapsed time in seconds: $ELAPSED"

# Indicate completion of batch job
echo "Batch job completed!"