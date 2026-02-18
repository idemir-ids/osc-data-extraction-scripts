💬 Important

On June 26 2024, Linux Foundation announced the merger of its financial services umbrella, the Fintech Open Source Foundation (`FINOS <https://finos.org>`_), with OS-Climate, an open source community dedicated to building data technologies, modelling, and analytic tools that will drive global capital flows into climate change mitigation and resilience; OS-Climate projects are in the process of transitioning to the `FINOS governance framework <https://community.finos.org/docs/governance>`_; read more on `finos.org/press/finos-join-forces-os-open-source-climate-sustainability-esg <https://finos.org/press/finos-join-forces-os-open-source-climate-sustainability-esg>`_


===========================
osc-data-extraction-scripts
===========================


.. image:: https://img.shields.io/badge/OS-Climate-blue
  :alt: An OS-Climate Project
  :target: https://os-climate.org/

.. image:: https://img.shields.io/badge/slack-osclimate-brightgreen.svg?logo=slack
  :alt: Join OS-Climate on Slack
  :target: https://os-climate.slack.com

.. image:: https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white
  :alt: Source code on GitHub
  :target: https://github.com/idemir-ids/osc-data-extraction-scripts


OSC Data Extraction (Ubuntu/Debian + NVIDIA GPU)
================================================

Introduction
------------

The OS‑Climate Data Extraction Pipeline transforms long, complex PDF reports into structured KPI datasets ready for use in the OS‑Climate (OSC) platform. The pipeline targets sustainability and climate disclosures that often mix narrative text with dense tables and varied layouts. Its aim is to automate and standardize KPI capture at scale while preserving the context needed for traceability and review.

At the core of the system are two complementary extraction engines that mirror how humans read reports: a transformer‑based component excels at understanding free‑flowing text and longer sentences, while a rule‑based component is optimized for structured tables and spatially aligned data. Outputs from both are harmonized into a single CSV, resolving overlaps so users receive one clean, consolidated view of KPIs per document. This unified approach balances precision with coverage across the diverse formats found in real‑world disclosures.

The transformer path is trained to both find and extract. One model assesses paragraph relevance for a given KPI, filtering the document to the most promising passages; a second model then extracts the KPI value or qualitative statement, along with supporting text. Training relies on curated annotations drawn from actual PDF content and benefits from transfer learning with pre‑trained BERT‑based models, making fine‑tuning efficient even with modest labeled datasets when GPU acceleration is available. Model artifacts are stored with their weights and tokenizer configurations to enable straightforward reuse and retraining as requirements evolve.

The rule‑based path takes a deterministic approach that shines in clean, well‑structured tables. It combines predefined rules, regular expressions, and spatial layout cues derived from a customized xpdf workflow that preserves coordinates during rendering. By matching against explicit KPI definitions, the extractor can return the KPI name, value, unit (where present), and year with high precision, providing a reliable counterpoint to the transformer’s strengths in narrative text.

Engineered for throughput and robustness, the pipeline is designed to process on the order of thousands of reports per day (for documents up to roughly a hundred pages) on standard hardware. Its modular architecture isolates components so that changes in document styles or KPI definitions can be accommodated without destabilizing the overall system. Just as importantly, the outputs maintain transparency: each extracted KPI links back to the paragraph and page it came from, enabling rapid human verification and iterative improvement of rules, models, and training data over time.

Together, these design choices make the pipeline a practical bridge from heterogeneous PDF disclosures to consistent, analyzable KPI datasets.

The remainder of this README guides you through setting up the GPU‑enabled environment, training the transformer models with your annotations, running both extraction paths, and producing the unified CSV outputs for downstream analysis within the OS‑Climate ecosystem.

What you will do
----------------

- Prepare a Linux host with an NVIDIA GPU and Docker.
- Install the NVIDIA Container Toolkit so Docker can access your GPU.
- Launch an Ubuntu 24.04 container with GPU access.
- Clone the scripts, install dependencies, and optionally start a lightweight web server.
- Train models (guided script), then run KPI extraction on PDFs.
- Inspect results and optionally expose inputs/outputs via a simple web server.

Hardware requirements
---------------------

- A Linux machine with a CUDA 11+ capable GPU (example: NVIDIA A10G).

Prerequisites (Host, Ubuntu/Debian)
-----------------------------------

1) Install Docker

- Follow the official installation guide:
  https://docs.docker.com/engine/install/

2) Install the NVIDIA Container Toolkit

- The following commands configure the toolkit repository, install it, and restart Docker. Run these on the host:

.. code-block:: bash

   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
   sudo apt-get update
   sudo apt-get install -qq nvidia-container-toolkit

   sudo systemctl restart docker

Verify GPU access on the host
-----------------------------

- Confirm that the NVIDIA driver and GPUs are visible:

.. code-block:: bash

   nvidia-smi

- Example output (yours may differ):

.. code-block:: text

   Wed Feb 18 14:47:42 2026
   +-----------------------------------------------------------------------------+
   | NVIDIA-SMI 525.85.12    Driver Version: 525.85.12    CUDA Version: 12.0     |
   |-------------------------------+----------------------+----------------------+
   | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
   | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
   |                               |                      |               MIG M. |
   |===============================+======================+======================|
   |   0  NVIDIA A10G         On   | 00000000:00:1E.0 Off |                    0 |
   |  0%   20C    P8    14W / 300W |      0MiB / 23028MiB |      0%      Default |
   |                               |                      |                  N/A |
   +-------------------------------+----------------------+----------------------+

   +-----------------------------------------------------------------------------+
   | Processes:                                                                  |
   |  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
   |        ID   ID                                                   Usage      |
   |=============================================================================|
   |  No running processes found                                                 |
   +-----------------------------------------------------------------------------+

Start a Docker container with GPU access (Host)
-----------------------------------------------

Tip: If you want to detach and come back later, consider running in a terminal multiplexer (e.g., screen or tmux).

- Run Docker with no folder mounted (everything kept inside the container):

.. code-block:: bash

   docker run --gpus all -ti -p 80:80 ubuntu:24.04 /bin/bash

- Alternative: mount an external folder (example: ``/osc``) so PDFs or other data on the host are accessible inside the container:

.. code-block:: bash

   docker run --gpus all -v /osc:/osc -ti -p 80:80 ubuntu:24.04 /bin/bash

Inside the Docker container
---------------------------

Update package lists and install Git
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   apt-get update
   apt-get install -y git

Create workspace and clone scripts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   mkdir /data-extraction
   cd /data-extraction

   git clone https://github.com/idemir-ids/osc-data-extraction-scripts

Copy helper scripts locally and make them executable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- You can adapt these scripts according to your requirements. By default, they work without adjustments, provided you follow the folder structure outlined here.

.. code-block:: bash

   cp osc-data-extraction-scripts/install.sh .
   cp osc-data-extraction-scripts/websrv.sh .
   cp osc-data-extraction-scripts/train.sh .
   cp osc-data-extraction-scripts/script.sh .
   chmod +x *.sh

Install all components
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   ./install.sh

- After installation, list the directory to verify structure:

.. code-block:: bash

   ll

- Expected contents (for reference):

.. code-block:: text

   ./
   ../
   install.sh*    # The installation script
   libpng12-0_1.2.54-1ubuntu1.1+1~ppa0~eoan_amd64.deb
   osc-data-extraction-scripts/           # Git repo for the main scripts
   osc-rule-based-extractor/              # Git repo for the rule-based extractor (for TABLE extraction)
   osc-transformer-based-extractor/       # Git repo for the transformer-based extractor (for TEXT extraction)
   osc-transformer-presteps/              # Git repo for presepts of the transformer-based extractor
   osc-xpdf-mod/                          # Git repo for the xpdf module (needed for the RB extractor)
   rb_files/
   script.sh*
   train.sh*
   venv_presteps/                         # Virtual Environments for the individual components
   venv_rb/
   venv_tb/
   websrv.sh*

Optional: start a simple web server
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- This sets up a simple web server (lighttpd) and creates and exposes ``/data-extraction/inputs_www`` and ``/data-extraction/outputs_www`` for easy access:

.. code-block:: bash

   ./websrv.sh

Train models (guided)
~~~~~~~~~~~~~~~~~~~~~

- Run the training script. It will guide you through steps 1–7. You can stop and resume as needed, or use the provided demo files.

.. code-block:: bash

   ./train.sh

- After training, two new folders appear in ``/data-extraction``:

.. code-block:: text

   rb_files/  # Files for RB extractor. This contains KPI specifications in form of YAML files. You can adjust or change them as needed.
   tb_files/  # Files for TB extractor. This contains the trained models. You should not change them manually, but instead use the train.sh script if you need modifications.

Prepare inputs and outputs
~~~~~~~~~~~~~~~~~~~~~~~~~~

- Create folders for input PDFs and extracted KPI outputs. If you want different folders, adjust the variables ``SOURCE``, ``TARGET``, and optionally ``SELECTION`` inside ``script.sh``.

.. code-block:: bash

   mkdir /data-extraction/inputs
   mkdir /data-extraction/outputs

- Place PDFs to be processed in the input folder. Alternatively, use the demo PDF from the repository:

.. code-block:: bash

   cp osc-transformer-based-extractor/demo/data/shell_annual_report_2019.pdf inputs/

- Verify the input folder:

.. code-block:: bash

   ll inputs

- Expected:

.. code-block:: text

   ./
   ../
   shell_annual_report_2019.pdf

Run KPI extraction
~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   ./script.sh

Inspect results
~~~~~~~~~~~~~~~

- Extracted KPIs (one CSV per PDF) and JSONs with extracted paragraphs will be in the output folder:

.. code-block:: bash

   ll outputs

- Expected:

.. code-block:: text

   ./
   ../
   shell_annual_report_2019.pdf.csv
   shell_annual_report_2019_output.json

Notes on training quality
-------------------------

- If you only trained the model with the provided demo material, do not expect strong results from the transformer-based (TB) extractor (text extraction). You need many, meaningful annotations to achieve good quality. These are not provided in this repository.
- To create an annotations file, follow the fixed format (Excel sheet with specified column names). Use the demo annotations file as a template and extend it with your data:
  ``osc-transformer-based-extractor/demo/data/annotations_training.xlsx``

Optional: expose inputs/outputs via webserver
---------------------------------------------

- If you started the web server, you can copy files into the web-accessible folders for easy download and inspection:

.. code-block:: bash

   cp inputs/* inputs_www/
   cp outputs/* outputs_www/

Additional tips
---------------

- The container defaults to running as root, so ``apt-get`` does not require ``sudo`` inside the container.
- If ``ll`` is not recognized, it may be an alias not enabled by default. You can use ``ls -alF`` instead, but the examples keep the original ``ll`` for consistency.
- Ensure your host NVIDIA driver version supports the CUDA version indicated by ``nvidia-smi`` and is compatible with your GPU and the containerized workloads.
