#!/bin/bash

set -x
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

env >> /tmp/environment.txt

git clone -q --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
chmod 600 ${PRIVATE_KEY}
ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} stack@${ORCHESTRATION_HOST} rm -f ./run_ocm_api_load.sh ./environment.txt

echo "Transfering the environment variables file and run_ocm_api_load.sh to the orchestration host"
scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /tmp/environment.txt $SCRIPT_DIR/run_ocm_api_load.sh stack@${ORCHESTRATION_HOST}:~/

echo "Running ocm-load-test inside $ORCHESTRATION_HOST"
ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} stack@${ORCHESTRATION_HOST} ./run_ocm_api_load.sh
