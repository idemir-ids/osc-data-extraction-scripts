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
SELECTION="*.pdf"    # File selection pattern, example: "e15*.pdf"

### Functions

# Function to merge output files
_merge_files() {
    # Exit on error
    set -e

    local FOLDER="$1"

    # Check if folder exists
    if [ ! -d "$FOLDER" ]; then
        echo "Error: Folder '$FOLDER' does not exist"
        return 1
    fi

    # Change to the folder (in a subshell to preserve current directory)
    (
        cd "$FOLDER"

        echo "Working in folder: $(pwd)"

        # Find and delete the xlsx file ending with "_unverified"
        local UNVERIFIED_FILE=$(find . -maxdepth 1 -name "*_unverified.xlsx" -type f | head -n 1)
        if [ -n "$UNVERIFIED_FILE" ]; then
            echo "Deleting: $UNVERIFIED_FILE"
            rm "$UNVERIFIED_FILE"
        else
            echo "Warning: No file ending with '_unverified.xlsx' found"
        fi

        # Find and remember the CSV file name
        local CSV_FILE=$(find . -maxdepth 1 -name "*.csv" -type f | head -n 1)
        if [ -z "$CSV_FILE" ]; then
            echo "Error: No CSV file found"
            return 1
        fi

        # Remove the ./ prefix if present
        CSV_FILE=$(basename "$CSV_FILE")
        echo "Found CSV file: $CSV_FILE"
        local ORIGINAL_CSV_NAME="$CSV_FILE"

        # Find the remaining xlsx file (not the unverified one)
        local XLSX_FILE=$(find . -maxdepth 1 -name "*.xlsx" -type f | head -n 1)
        if [ -z "$XLSX_FILE" ]; then
            echo "Error: No XLSX file found"
            return 1
        fi

        XLSX_FILE=$(basename "$XLSX_FILE")
        echo "Found XLSX file: $XLSX_FILE"

        # Rename the files
        echo "Renaming '$CSV_FILE' to '000-input.csv'"
        mv "$CSV_FILE" "000-input.csv"

        echo "Renaming '$XLSX_FILE' to '000-input.xlsx'"
        mv "$XLSX_FILE" "000-input.xlsx"

        # Activate the Python virtual environment
        source /data-extraction/venv_presteps/bin/activate

        # Run merge command
        echo "osc-transformer-presteps merge-output run-merge-output 000-input.csv 000-input.xlsx '$ORIGINAL_CSV_NAME'"
        osc-transformer-presteps merge-output run-merge-output 000-input.csv 000-input.xlsx "$ORIGINAL_CSV_NAME"

        # Deactivate the virtual environment
        deactivate

        # Delete temporary files
        rm 000-input.csv 2>/dev/null
        rm 000-input.xlsx 2>/dev/null

        echo "Done!"
    )
}

# Function to run the OSC pipeline
_run_osc_pipeline() {
    local input_dir="$1"      # Input directory for the pipeline
    local output_dir="$2"     # Output directory for the pipeline
    local log_dir="$3"        # Log directory for the pipeline
    local rb_work_dir="$4"    # Work directory for rule-based extraction
    local tb_work_dir="$5"    # Work directory for transformer-based extraction
    
    
    ##### OSC Transformer Presteps ###
    echo "OSC Transformer Presteps" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_presteps/bin/activate
    
    # Run the osc-transformer-presteps ( TODO : Very slow for e15dc57a77884d11a9d0d19116e4800d.pdf )
    echo "osc-transformer-presteps extraction run-local-extraction '$input_dir' --output-folder='$output_dir' --logs-folder='$log_dir' --force"
    osc-transformer-presteps extraction run-local-extraction "$input_dir" --output-folder="$output_dir" --logs-folder="$log_dir" --force
    
    # Deactivate the virtual environment
    deactivate
    
    
    ##### OSC Rule-based KPI Extraction ###
    echo "OSC Rule-based KPI Extraction" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_rb/bin/activate
    
    # Run the rule-based-extractor
    echo "osc-rule-based-extractor --pdftohtml_mod_executable /data-extraction/osc-xpdf-mod/bin/pdftohtml_mod --raw_pdf_folder '$input_dir' --working_folder '$rb_work_dir' --kpi_folder '/data-extraction/rb_files/kpi_specs' --output_folder '$output_dir' --verbosity 0 > '$log_dir/rb.log' 2>/dev/null"
    osc-rule-based-extractor --pdftohtml_mod_executable /data-extraction/osc-xpdf-mod/bin/pdftohtml_mod --raw_pdf_folder "$input_dir" --working_folder "$rb_work_dir" --kpi_folder "/data-extraction/rb_files/kpi_specs" --output_folder "$output_dir" --verbosity 0 > "$log_dir/rb.log" 2>/dev/null
    
    # Deactivate the virtual environment
    deactivate


    ##### OSC Transformer-based KPI Extraction ###
    echo "OSC Transformer-based KPI Extraction" 
    
    # Activate the Python virtual environment
    source /data-extraction/venv_tb/bin/activate
    
    # Run the transformer-based-extractor
    
    echo "Step 1: Run relevance inference"
    mkdir -p "$tb_work_dir/infer_output"
    echo "osc-transformer-based-extractor relevance-detector inference '$output_dir' '/data-extraction/tb_files/curation/input/kpi_mapping.csv' '$tb_work_dir/infer_output' '/data-extraction/tb_files/relevance/saved_model/rel_model' '/data-extraction/tb_files/relevance/saved_model/rel_model' 16 0.5"
    osc-transformer-based-extractor relevance-detector inference "$output_dir" "/data-extraction/tb_files/curation/input/kpi_mapping.csv" "$tb_work_dir/infer_output" "/data-extraction/tb_files/relevance/saved_model/rel_model" "/data-extraction/tb_files/relevance/saved_model/rel_model" 16 0.5
    
    echo "Step 2: Run KPI inference"
    mkdir -p "$tb_work_dir/kpidetect/input"
    if [ -f "$tb_work_dir/infer_output/combined_inference/"*.xlsx ]; then
        cp "$tb_work_dir/infer_output/combined_inference/"*.xlsx "$tb_work_dir/kpidetect/input/rel_results.xlsx"
    fi
    
    echo "osc-transformer-based-extractor kpi-detection inference '$tb_work_dir/kpidetect/input/rel_results.xlsx' '$output_dir/' '/data-extraction/tb_files/kpidetect/saved_model/model01'"
    osc-transformer-based-extractor kpi-detection inference "$tb_work_dir/kpidetect/input/rel_results.xlsx" "$output_dir/" "/data-extraction/tb_files/kpidetect/saved_model/model01"


    # Deactivate the virtual environment
    deactivate

    _merge_files "$output_dir/"

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
    local tb_work_dir="$temp_dir/tb_work"
    mkdir -p "$input_dir" "$output_dir" "$log_dir" "$rb_work_dir" "$tb_work_dir"
    
    # Copy the file to the input directory
    cp "$filename" "$input_dir/$base_filename"
    
    # Run the pipeline on the file
    _run_osc_pipeline "$input_dir" "$output_dir" "$log_dir" "$rb_work_dir" "$tb_work_dir"
    
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
THREADS=1 #$($NPROC_CMD) # Number of threads for parallel processing

# Install if not already installed
chmod +x install.sh
./install.sh

# Display script information
echo "OS-Climate / Data Extraction Team"
echo "Bulk execution script"

# Display number of parallel threads
echo "Parallel threads for batch processing: $THREADS"

# Record start time
START=$(date '+%s')

# Display number of input files to process
echo -n "Input files to process: "
find "$SOURCE" -type f -name "$SELECTION" | wc -l

# Choose any one of the following (other comment out!)

# 1) Process files in parallel using the specified number of threads
# find "$SOURCE" -type f -name "$SELECTION" | parallel -j "$THREADS" _process_files {} "$TARGET"

# 2) Process files sequentially as alternative for debugging
find "$SOURCE" -type f -name "$SELECTION" | while read -r file; do
  _process_files "$file" "$TARGET"
done

# Record end time and calculate elapsed time
END=$(date '+%s')
ELAPSED=$((END-START))
echo "Elapsed time in seconds: $ELAPSED"

# Indicate completion of batch job
echo "Batch job completed!"