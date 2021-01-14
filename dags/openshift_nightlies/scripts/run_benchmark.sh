#!/bin/bash

set -eux

while getopts b: flag
do
    case "${flag}" in
        b) benchmark=${OPTARG};;
    esac
done


setup(){
    echo "HELLO"
    mkdir /home/airflow/workspace
    echo "hello"
    cd /home/airflow/workspace
    git clone https://github.com/cloud-bulldozer/e2e-benchmarking
    export KUBECONFIG=~/.kube/config
    export BUILD_NUMBER=test

    rm /tmp/uperf_$BUILD_NUMBER.status || true
    export BENCHMARK_STATUS_PATH=/tmp/uperf_$BUILD_NUMBER.status
    echo "BENCHMARK_STATUS_FILE=$BENCHMARK_STATUS_PATH" > uperf.properties

    curl -L $OPENSHIFT_CLIENT_LOCATION -o openshift-client.tar.gz
    tar -xzf openshift-client.tar.gz

    export PATH=$PATH:$(pwd)
}

echo "HELLO"
setup
cd e2e-benchmarking/network-perf
./smoke_test.sh test_cloud $KUBECONFIG
