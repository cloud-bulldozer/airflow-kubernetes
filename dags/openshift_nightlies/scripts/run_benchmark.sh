 #!/bin/bash
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
    echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
    git clone -b ${E2E_BENCHMARKING_BRANCH} ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
    cp /home/airflow/auth/config /home/airflow/workspace/config
    export KUBECONFIG=/home/airflow/workspace/config
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

run_baremetal_benchmark(){
    echo "Baremetal Benchmark will be began.."
    echo "Orchestration host --> $ORCHESTRATION_HOST"

    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
    export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    echo "Transfering the environment variables to the orchestration host"
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /tmp/environment.txt root@${ORCHESTRATION_HOST}:/tmp/environment_new.txt

    echo "Starting e2e script $workload..."
    ssh -t -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} << EOF

    export KUBECONFIG=/home/kni/clusterconfigs/auth/kubeconfig
    export BENCHMARK=${TASK_GROUP}
    while read line; do export \$line; done < /tmp/environment_new.txt
    # clean up the temporary environment file
    rm -rf /tmp/environment_new.txt
    rm -rf /home/kni/ci_${TASK_GROUP}_workspace
    mkdir /home/kni/ci_${TASK_GROUP}_workspace
    pushd /home/kni/ci_${TASK_GROUP}_workspace

    if [[ ${workload} == "icni" ]]; then
        git clone -b main https://github.com/redhat-performance/web-burner
        pushd web-burner
        echo "Running $WORKLOAD_TEMPLATE workload at $SCALE scale"
        eval "$command $WORKLOAD_TEMPLATE $SCALE"
    else
        echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
        git clone -b ${E2E_BENCHMARKING_BRANCH} ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
        pushd e2e-benchmarking/workloads/$workload
        eval "$command"
    fi
EOF
    if [[ $? != 0 ]]; then
        exit 1
    fi
}

if [[ $PLATFORM == "baremetal" ]]; then
    export UUID=$(uuidgen | head -c16)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')
    env >> /tmp/environment.txt
    run_baremetal_benchmark
    echo $UUID
else
    setup
    cd /home/airflow/workspace
    ls
    cd e2e-benchmarking/workloads/$workload
    export UUID=$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')-$(uuidgen | head -c16)
    
    eval "$command"
    benchmark_rv=$?

    if [[ ${MUST_GATHER_EACH_TASK} == "true" && ${benchmark_rv} -eq 1 ]] ; then
        echo -e "must gather collection enabled for this task"
        cd ../../utils/scale-ci-diagnosis
        export OUTPUT_DIR=$PWD
        export PROMETHEUS_CAPTURE=false
        export PROMETHEUS_CAPTURE_TYPE=full
        export OPENSHIFT_MUST_GATHER=true
        export STORAGE_MODE=snappy
        export WORKLOAD=$AIRFLOW_CTX_TASK_ID-must-gather
        ./ocp_diagnosis.sh > /dev/null
    fi
    echo $UUID
    exit $benchmark_rv

fi
