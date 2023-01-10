#!/bin/bash
# shellcheck disable=SC2155
set -ex

export INDEXDATA=()

while getopts v:a:j:o: flag
do
    case "${flag}" in
        o) operation=${OPTARG};;
        *) echo "ERROR: invalid parameter ${flag}" ;;
    esac
done

setup(){
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

    echo "User: ${GIT_USER} ORCHESTRATION_HOST: ${ORCHESTRATION_HOST}"
    if [[ $GIT_USER != "perf-ci" && ${ORCHESTRATION_HOST} == "airflow-ocm-jumphost.rdu2.scalelab.redhat.com" ]]; then
	echo "$GIT_USER not allowed to use CI host ${ORCHESTRATION_HOST}"
	exit 1
    fi

    git clone -q --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
    export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    # TESTDIR and UUID will be same for ocm-api-load operation. cleanup operation uses different TESTDIR to get unaffected by ocm-api-load operation failures. Cleanup still retrieves UUID and removes /tmp/${UUID} on ORCHESTRATION_HOST
    export TESTDIR=$(uuidgen | head -c8)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')
    export UUID=${UUID:-${TESTDIR}}
    echo "# UUID: ${UUID} TESTDIR: ${TESTDIR} "

    env >> /tmp/environment.txt

    # Create temp directory to run tests (simulatenous runs will have their own temp directories)
    ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} "mkdir /tmp/$TESTDIR"

    echo "Transfering the environment variables file and all scripts to ${ORCHESTRATION_HOST}:/tmp/$TESTDIR/"
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /tmp/environment.txt $SCRIPT_DIR/* root@${ORCHESTRATION_HOST}:/tmp/$TESTDIR/
}

setup

if [[ "$operation" == "ocm-api-load" ]]; then
    echo "Running ocm-load-test inside $ORCHESTRATION_HOST"
    ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} /tmp/$TESTDIR/run_ocm_api_load.sh
elif [[ "$operation" == "cleanup" ]]; then
    echo "Running cleanup script inside $ORCHESTRATION_HOST"
    ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} /tmp/$TESTDIR/cleanup_clusters.sh
fi

