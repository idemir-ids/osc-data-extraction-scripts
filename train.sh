#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 The Linux Foundation

# OS-Climate / Data Extraction Team

# Script repository/location:
# https://github.com/os-climate/osc-data-extraction-scripts

### Bulk training script ###

set -o pipefail
# set -vx  # Uncomment to enable verbose output for debugging


function create_folder_strcuture() {
  echo "Creating folder structure..."
  mkdir -p /data-extraction/tb_files/extraction/input
  mkdir -p /data-extraction/tb_files/extraction/output
  mkdir -p /data-extraction/tb_files/extraction/log
  mkdir -p /data-extraction/tb_files/curation/input
  mkdir -p /data-extraction/tb_files/curation/output
  mkdir -p /data-extraction/tb_files/curation/log
  mkdir -p /data-extraction/tb_files/relevance/input
  mkdir -p /data-extraction/tb_files/relevance/input_json
  mkdir -p /data-extraction/tb_files/relevance/infer_output
  mkdir -p /data-extraction/tb_files/relevance/saved_model
  mkdir -p /data-extraction/tb_files/kpidetect/input
  mkdir -p /data-extraction/tb_files/kpidetect/output
  mkdir -p /data-extraction/tb_files/kpidetect/saved_model
  echo "Done. You may now continue with copying demo material (optional), or extracting input pdfs."
}

function copy_demo_material() {
  echo "Copying demo materials..."
  if [ ! -d "/data-extraction/osc-transformer-presteps" ]; then
    CURDIR=$(pwd)
    mkdir -p /data-extraction
    cd /data-extraction
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata  > /dev/null 2>&1
    apt-get install -qq git  > /dev/null 2>&1
    git clone --quiet https://github.com/idemir-ids/osc-transformer-presteps
    cd "$CURDIR"
  fi
  rm /data-extraction/tb_files/extraction/input/* 2> /dev/null
  rm /data-extraction/tb_files/curation/input/* 2> /dev/null
  cp --verbose -r /data-extraction/osc-transformer-presteps/demo/extraction/input /data-extraction/tb_files/extraction/
  cp --verbose -r /data-extraction/osc-transformer-presteps/demo/curation/input /data-extraction/tb_files/curation/
  echo "Done. You may now continue with extracting input pdfs."
}

function extract_input_pdf() {
  echo "Extracting input PDF..."
  CURDIR=$(pwd)
  source /data-extraction/venv_presteps/bin/activate
  cd /data-extraction/tb_files/extraction/
  rm /data-extraction/tb_files/extraction/output/*.json 2> /dev/null # delete old json data
  osc-transformer-presteps extraction run-local-extraction "input/" --output-folder="output/" --logs-folder="log/" --force
  deactivate
  echo "Copying extraction output into curation input (JSON files)"
  rm /data-extraction/tb_files/curation/input/*.json 2> /dev/null
  cp --verbose /data-extraction/tb_files/extraction/output/*.json /data-extraction/tb_files/curation/input/
  cd "$CURDIR"
  echo "Done. You may now continue with curation."
}

function curate_input_data() {
  echo "Curate input data (JSON + KPI Mapping + Annotations) ..."
  CURDIR=$(pwd)
  rm /data-extraction/tb_files/curation/output/Curated_dataset*.csv 2> /dev/null # delete old curation data
  source /data-extraction/venv_presteps/bin/activate
  cd /data-extraction/tb_files/curation/
  osc-transformer-presteps relevance-curation run-local-curation --create_neg_samples --neg_sample_rate 5 'input/' 'input/test_annotations.xlsx' 'input/kpi_mapping.csv' 'output/'
  deactivate
  echo "Copying curation output into training input (Curated_dataset.csv)"
  # there is only such csv file, so the following command will work
  cp --verbose /data-extraction/tb_files/curation/output/Curated_dataset*.csv /data-extraction/tb_files/relevance/input/Curated_dataset.csv
  cp --verbose /data-extraction/tb_files/curation/output/Curated_dataset*.csv /data-extraction/tb_files/kpidetect/input/Curated_dataset.csv
  cd "$CURDIR"
  echo "Done. You may now continue with training relevance detector."
}


function train_relevance_detector() {
  echo "Training relevance detector..."
  CURDIR=$(pwd)
  source /data-extraction/venv_tb/bin/activate
  cd /data-extraction/tb_files/relevance/
  osc-transformer-based-extractor relevance-detector fine-tune \
    "input/Curated_dataset.csv" \
    "bert-base-uncased" \
    2 \
    128 \
    3 \
    16 \
    0.00005 \
    "saved_model/" \
    "rel_model" \
    500
  deactivate
  cd "$CURDIR"
  echo "======================================================================================"
  echo "Done. You may now continue with training KPI detector."
}

## === LEGACY ====
#function train_kpi_detector() {
#  echo "Training KPI detector..."
#  CURDIR=$(pwd)
#  source /data-extraction/venv_tb/bin/activate
#  cd /data-extraction/tb_files/kpidetect
#  osc-transformer-based-extractor kpi-detection fine-tune \
#      "input/Curated_dataset.csv" \
#      "bert-base-uncased" \
#      128 \
#      7 \
#      16 \
#      5e-5 \
#      "saved_model/" \
#      "model01" \
#      500
#  deactivate
#  cd "$CURDIR"
#  echo "======================================================================================"
#  echo "Congratulations! We are now ready for inference. :-) "
#}


function train_kpi_detector() {
  echo "Training KPI detector..."
  CURDIR=$(pwd)
  source /data-extraction/venv_tb/bin/activate
  cd /data-extraction/tb_files/kpidetect
  osc-transformer-based-extractor kpi-detection fine-tune \
      "input/Curated_dataset.csv" \
      "deepset/bert-base-uncased-squad2" \
      512 \
      3 \
      16 \
      5e-5 \
      "saved_model/" \
      "model01" \
      500
  deactivate
  cd "$CURDIR"
  echo "======================================================================================"
  echo "Congratulations! We are now ready for inference. :-) "
}


function show_menu() {
  echo ""
  echo "=== Welcome to Training for OSC Transformer-based Extraction ==="
  echo "How does it work?"
  echo "1)  First, you need to create the folder structure"
  echo "Then, you need to copy training data into the input folders. Put files into all"
  echo "folders, that are indicated by 'PUT INPUT DATA' in the diagram below!"
  echo "2) Alternatively, you can use demo materials as input that ship with the repo"
  echo "The folder structure will look like this:"
  echo "/data-extraction/                                                                     "
  echo "├─ tb_files/                                                                          "
  echo "│  ├─ extraction/                                                                     "
  echo "│  │  ├─ input/                  # PDFs here                   <<<<=== PUT INPUT DATA "
  echo "│  │  ├─ output/                 # JSON output here                                   "
  echo "│  │  └─ log/                                                                         "
  echo "│  ├─ curation/                                                                       "
  echo "│  │  ├─ input/                                                                       "
  echo "│  │  │  ├─ Test_output.json     # from extraction                                    "
  echo "│  │  │  ├─ test_annotations.xlsx                              <<<<=== PUT INPUT DATA "
  echo "│  │  │  └─ kpi_mapping.csv                                    <<<<=== PUT INPUT DATA "
  echo "│  │  ├─ output/                 # may be ignored by current version                  "
  echo "│  │  └─ log/                                                                         "
  echo "│  ├─ relevance/                                                                      "
  echo "│  │  ├─ input/                                                                       "
  echo "│  │  │  └─ Curated_dataset.csv           # from presteps curation                    "
  echo "│  │  ├─ input_json/                      # extracted JSONs copied here for inference "
  echo "│  │  ├─ infer_output/                    # relevance inference output                "
  echo "│  │  └─ saved_model/                                                                 "
  echo "│  │     └─ rel_model/                    # saved relevance model                     "
  echo "│  └─ kpidetect/                                                                      "
  echo "│     ├─ input/                                                                       "
  echo "│     │  ├─ Curated_dataset.csv           # for KPI training                          "
  echo "│     │  └─ rel_results.xlsx              # from relevance inference                  "
  echo "│     ├─ output/                          # KPI inference output                      "
  echo "│     └─ saved_model/                                                                 "
  echo "│        └─ model01/                      # saved KPI model                           "
  echo "3) Next, you can extract the input PDFs to JSON"
  echo "4) Next, you can curate the data (JSON + KPI Mapping + Annotations)"
  echo "5) Next, you can train the relevance detector"
  echo "6) Finally, you can train the KPI detector"
  echo "======================================================================================"
  echo "Pick your choice!"
  echo "1) Create folder structure"
  echo "2) Copy demo materials (only if you do NOT want to us your own training data)"
  echo "3) Extract input PDF to JSON"
  echo "4) Curate input data"
  echo "5) Train relevance detector"
  echo "6) Train KPI detector"
  echo "7) Exit"
  echo "======================================================================================"
}

while true; do
  show_menu
  read -p "Enter your choice [1-7]: " choice

  case $choice in
    1) create_folder_strcuture ;;
    2) copy_demo_material ;;
    3) extract_input_pdf ;;
    4) curate_input_data ;;
    5) train_relevance_detector ;;
    6) train_kpi_detector ;;
    7) echo "Have a nice day!"; exit 0 ;;
    *) echo "Invalid option!" ;;
  esac

  read -p "Press Enter to continue..."
done