<!--
[comment]: # SPDX-License-Identifier: Apache-2.0
[comment]: # SPDX-FileCopyrightText: 2024 The Linux Foundation
-->

# OS-Climate Data Extraction Scripts

## osc-data-extraction-scripts

Scripts to build/deploy the OS-Climate data extraction tooling

### Files

<!-- markdownlint-disable MD013 -->

| Name         | Description                                                                       |
| ------------ | --------------------------------------------------------------------------------- |
| Dockerfile   | Defines the steps required to build the data extraction tooling Docker container  |
| bootstrap.sh | Used to install Docker on a server instance [Debian/Ubuntu/Fedora/Amazon Linux]   |
| build.sh     | Thin shell script/wrapper to build the Docker container                           |
| metadata     | Contains variable definitions/parameters describing the Docker container          |
| publish.sh   | Thin shell script/wrapper publish the Docker container to a registry              |
| run.sh       | Thin shell script/wrapper ro run the Docker container                             |
| install.sh   | Script copied into the Docker container; installs all components                  |
| train.sh     | Script copied into the Docker container; training relevance and kpi detector      |
| script.sh    | Script copied into the Docker container; uses GNU parallel to run data extraction |
| websrv.sh    | Script copied into the Docker container; setup web server for easy file access    |
| tag.sh       | Thin shell script/wrapper to tag the container with metadata                      |

<!-- markdownlint-enable MD013 -->

## bootstrap.sh

SSH to the EC2 instance, download the bootstrap.sh script, then run it:

```console
wget https://raw.githubusercontent.com/idemir-ids/osc-data-extraction-scripts/refs/heads/main/bootstrap.sh
chmod a+x bootstrap.sh
./bootstrap.sh
```

This script will take a vanilla EC2 server instance running the Linux operating
system and install Docker. Subsequent steps will mount a pre-determined EFS/NFS
volume which contains the raw PDF data set collected/aggregated by the
OS-Climate Data Extraction team.

Because of the EFS volume location, it will only run be possible to mount this
storage volume for server instances hosted in the AWS region: eu-west-2 (London)

Supported distributions are:

- Debian
- Ubuntu
- Fedora
- Amazon Linux

With minor modifications, the script should run on other distributions too.

The EFS mount used for demonstrations has the DNS name:

`fs-0abca58dcce09a51a.efs.eu-west-2.amazonaws.com`

The bootstrap.sh script will attempt to mount this under the location:

`/osc`

This will make a further directory available:

`/osc/data-extraction`

The Docker host can then be invoked to run the container and map the volume:

```console
docker run -v "$PWD":/data-extraction -ti ubuntu:24.04 /bin/bash
```

Navigating to /data-extraction inside the container will expose copies of the
scripts contained in this repository. The primary data processing script can be
invoked by doing:

```console
cd /data-extraction
./script.sh
```

The full operation of this script is described below.

For easy file access, there is also a webserver available. You can install and
run it by doing:

```console
cd /data-extraction
./websrv.sh
```

It will create two directories at /data-extraction, where you can copy input and
output files (inputs_www and outputs_www).

Alternatively, to directly invoke the primary data processing script in the
container, you can instead use the full Docker command below:

```console
docker run -v "$PWD":/data-extraction -ti ubuntu:22.04 /bin/bash /data-extraction/script.sh
```

By varying the EC2 instance type and sizing, the data extraction scripts can be
run in bulk and benchmarked for their performance. The data set is ~420GB in
size and contains ~80,000 PDF files.

## script.sh

This is the primary script that runs/executes the data extraction toolset. It
is designed to run on a Linux instance and/or inside a docker container. It
enumerates the number of processor cores available and invokes the data
extraction Python tooling with GNU parallel to perform as many operations as
possible in parallel.

The script obtains a list of files selected for processing by using a wildcard
pattern match against a directory containing PDF files. Every file returned by
the pattern match is then passed to the Python tooling via GNU parallel.

```console
SELECTION="e15*.pdf"
```

Since Docker containers can artificially be restricted to a reduced number of
processor cores, Docker therefore provides a simple way to test the tool
performance when given a variable number of cores on which to run jobs.

The function that performs the processing is defined as:

```console
_process_files() {
    echo "Processing: $1"
    sleep 3
}
```

The source directory containing PDF files for ingestion is by default:

```console
SOURCE="inputs"
```

To invoke the data extraction tooling, simply replace the sleep statement with
the code required to ingest and process files. The shell script counts the
time elapsed (in seconds) to run the batch job, making it trivial to compare
the performance under different numbers of cores, versions of code, or other
metrics.

### Notes on Performance/Benchmarking

The number of processor cores available to the script can be modified by
either changing the EC2 instance type, or capping the number exposed cores in
Docker. Rather than enumerating cores, the script can also be modified to wire
the number of cores to a fixed value.

## All Other Scripts

The other scripts supplied are related to the various functions involved in
building, tagging and uploading a docker container image. Unfortunately, due
to the number of Python dependencies, the container image currently makes
for a base image of ~10GB in size, which is too large for regular/casual use.
It probably does have some utility in that storing this in a high
performance/local registry will improve latency and cost when used regularly in
CI/CD pipelines or other scenarios where regular usage is guaranteed.

Mostly, these other scripts are provided for simple convenience and for the end
user that is perhaps less familiar with the semantics/use of the Docker CLI
tools.

### License

All repository code/contents are licensed under the Apache-2.0 license
