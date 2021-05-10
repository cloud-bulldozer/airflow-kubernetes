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
    export KUBECONFIG=/home/airflow/.kube/config
    export BUILD_NUMBER=test
    export RUN_ID=${AIRFLOW_CTX_DAG_ID}/${AIRFLOW_CTX_DAG_RUN_ID}/$AIRFLOW_CTX_TASK_ID

    rm /tmp/uperf_$BUILD_NUMBER.status || true
    export BENCHMARK_STATUS_PATH=/tmp/uperf_$BUILD_NUMBER.status
    echo "BENCHMARK_STATUS_FILE=$BENCHMARK_STATUS_PATH" > uperf.properties

    curl -L $OPENSHIFT_CLIENT_LOCATION -o openshift-client.tar.gz
    tar -xzf openshift-client.tar.gz

    export PATH=$PATH:$(pwd)

    if [[ ! -z "$KUBEADMIN_PASSWORD" ]]; then 
        oc login -u kubeadmin -p $KUBEADMIN_PASSWORD
    fi
}

setup
cd /home/airflow/workspace
ls
cd e2e-benchmarking/workloads/$workload

eval "$command"

