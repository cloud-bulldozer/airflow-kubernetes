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

run_baremetal_benchmark()
    echo "Baremetal Benchmark will be began.."
    echo "Orchestration host --> $ORCHESTRATION_HOST"

    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    chmod 600 ${PRIVATE_KEY}

    echo "Starting e2e script $workloads..."
    ssh -i ${PRIVATE_KEY} ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} << EOF

    mkdir /home/kni/ciworkspace
    pushd /home/kni/ciworkspace
    git clone -b baremetal-update https://github.com/jdowni000/e2e-benchmarking.git

    pushd e2e-benchmarking/workloads/$workload
    eval "$command"

    EOF
    echo "Finished e2e scripts for $workloads"

if [[ $PLATFORM == "baremetal" ]]; then
run_baremetal_benchmark
else
setup
cd /home/airflow/workspace
ls
cd e2e-benchmarking/workloads/$workload
eval "$command"
fi
