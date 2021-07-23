#!/bin/bash

set -eux

while getopts w:c: flag
do
    case "${flag}" in
        w) workload=${OPTARG};;
        c) command=${OPTARG};;
    esac
done


setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    git clone https://github.com/cloud-bulldozer/e2e-benchmarking

    cp /home/airflow/.kube/config /home/airflow/workspace/kubeconfig
    export KUBECONFIG=/home/airflow/workspace/kubeconfig
    curl http://dell-r510-01.perf.lab.eng.rdu2.redhat.com/msheth/gsheet_key.json > /tmp/key.json
    export GSHEET_KEY_LOCATION=/tmp/key.json
    export BUILD_NUMBER=test
    export RUN_ID=${AIRFLOW_CTX_DAG_ID}/${AIRFLOW_CTX_DAG_RUN_ID}/$AIRFLOW_CTX_TASK_ID
    export SNAPPY_RUN_ID=${AIRFLOW_CTX_DAG_ID}/${AIRFLOW_CTX_DAG_RUN_ID}

    rm /tmp/uperf_$BUILD_NUMBER.status || true
    export BENCHMARK_STATUS_PATH=/tmp/uperf_$BUILD_NUMBER.status
    echo "BENCHMARK_STATUS_FILE=$BENCHMARK_STATUS_PATH" > uperf.properties

    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc

    export PATH=$PATH:$(pwd)

    if [[ ! -z "$KUBEADMIN_PASSWORD" ]]; then 
        oc login -u kubeadmin -p $KUBEADMIN_PASSWORD --insecure-skip-tls-verify
    fi
}

setup
cd /home/airflow/workspace
ls
cd e2e-benchmarking/workloads/$workload

eval "$command"

