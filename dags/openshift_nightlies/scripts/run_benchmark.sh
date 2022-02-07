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
    export UUID=$(uuidgen | head -c16)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')

    if [[ ${workload} == "kraken" ]]; then
        echo "Orchestration host --> $CERBERUS_HOST"
        if [[ ! -d /tmp/perf-dept ]]; then
            git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
        fi
        export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
        export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
        chmod 600 ${PRIVATE_KEY}

        echo "Transfering the environment variables to the orchestration host"
        scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /home/airflow/auth/config root@${CERBERUS_HOST}:/root/.kube/config

        git clone -b main https://github.com/cloud-bulldozer/kraken-hub.git --depth=1 --single-branch
        cd kraken-hub
        declare -A chaos_test
        chaos_test=( [application-outages]=kraken:application-outages )
        echo “The ${command} is ${chaos_test[$command]}”
        cat env.sh |sed 's/export/echo/'|bash >container.env
        cat ${command}/env.sh |sed 's/export/echo/'|bash >>container.env
        scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} container.env root@$CERBERUS_HOST:/root/kraken-hub/
        ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST 'echo AWS_DEFAULT_REGION=`aws configure get default.region`>>/root/kraken-hub/aws.env'
        ssh  -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST 'echo AWS_ACCESS_KEY_ID=`aws configure get default.aws_access_key_id`>>/root/kraken-hub/aws.env'
        ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST 'echo AWS_SECRET_ACCESS_KEY=`aws configure get default.aws_secret_access_key`>>/root/kraken-hub/aws.env'
        echo "cd /root/kraken-hub/;podman run --env-file=container.env  --env-file=aws.env --name=application-outages --net=host  -v /root/.kube/config:/root/.kube/config:Z -d quay.io/openshift-scale/${chaos_test[$command]}"|ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST /bin/bash
        exit_code=`echo "podman inspect ${command} --format json"|ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  root@$CERBERUS_HOST /bin/bash | jq .[].State.ExitCode`
        if [[ 1 -ne $exit_code ]]; then
            echo "podman logs -f ${command}"|ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST /bin/bash
            exit_code=`echo "podman inspect ${command} --format json"|ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST /bin/bash | jq .[].State.ExitCode`
        fi
        echo "podman rm ${command}"|ssh -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@$CERBERUS_HOST /bin/bash
        benchmark_rv=$exit_code
    else
        setup
        cd /home/airflow/workspace
        ls
        cd e2e-benchmarking/workloads/$workload
        eval "$command"
        benchmark_rv=$?
    fi


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
