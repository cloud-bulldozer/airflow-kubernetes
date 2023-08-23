#!/bin/bash

set -exo pipefail

git clone --branch vchalla https://github.com/vishnuchalla/e2e-benchmarking.git /tmp/e2e-benchmarking
/tmp/e2e-benchmarking/utils/index.sh