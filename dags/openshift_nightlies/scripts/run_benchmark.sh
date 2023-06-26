#!/bin/bash

while getopts w:c: flag
do
    case "${flag}" in
        w) workload=${OPTARG};;
        c) command=${OPTARG};;
    esac
done

if [[ -z ${command} ]]; then
  echo "Missing -c flag"
  exit 1
fi


setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    cp /home/airflow/auth/config /home/airflow/workspace/config
    export KUBECONFIG=/home/airflow/workspace/config
    export GSHEET_KEY_LOCATION=/tmp/key.json
    export RUN_ID=${AIRFLOW_CTX_DAG_ID}/${AIRFLOW_CTX_DAG_RUN_ID}/$AIRFLOW_CTX_TASK_ID
    export SNAPPY_RUN_ID=${AIRFLOW_CTX_DAG_ID}/${AIRFLOW_CTX_DAG_RUN_ID}
    echo "cpt: true" > metadata.yml

    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc

    export PATH=$PATH:$(pwd)

    if [[ ! -z "$KUBEADMIN_PASSWORD" ]] && [[ $PLATFORM == "aro" ]]; then
        oc login -u kubeadmin -p $KUBEADMIN_PASSWORD --insecure-skip-tls-verify
    fi
    if [[ ! -z $MGMT_KUBECONFIG_SECRET ]]; then
        unset KUBECONFIG # Unsetting Hostedcluster kubeconfig, will fall back to Airflow cluster kubeconfig
        kubectl get secret $MGMT_KUBECONFIG_SECRET -o json | jq -r '.data.config' | base64 -d > /home/airflow/workspace/mgmt_kubeconfig
        export MC_KUBECONFIG="/home/airflow/workspace/mgmt_kubeconfig"
        export KUBECONFIG=/home/airflow/workspace/config
    fi
}

run_baremetal_benchmark(){
    echo "Baremetal Benchmark will be began.."
    echo "Orchestration host --> $ORCHESTRATION_HOST"

    git clone -q --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
    export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    echo "Transfering the environment variables to the orchestration host"
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /tmp/environment.txt root@${ORCHESTRATION_HOST}:/tmp/environment_new.txt

    echo "Starting e2e script $workload..."
    ssh -t -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} << EOF

    export KUBECONFIG=/home/kni/clusterconfigs/auth/kubeconfig
    export BENCHMARK=${TASK_GROUP}
    cat /tmp/environment_new.txt | awk -v x="'" -F "=" '{print "export " \$1"="x\$2x}' > vars.sh
    source vars.sh
    rm -rf /tmp/environment_new.txt vars.sh
    rm -rf /home/kni/ci_${TASK_GROUP}_workspace
    mkdir /home/kni/ci_${TASK_GROUP}_workspace
    pushd /home/kni/ci_${TASK_GROUP}_workspace

    if [[ ${workload} == "icni" ]]; then
        git clone -q --depth=1 --single-branch -b main https://github.com/redhat-performance/web-burner
        pushd web-burner
        echo "Running $WORKLOAD_TEMPLATE workload at $SCALE scale"
        eval "$command $WORKLOAD_TEMPLATE $SCALE"
    else
        echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
        git clone -q -b ${E2E_BENCHMARKING_BRANCH} ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
        pushd e2e-benchmarking/workloads/$workload
        eval "$command"
    fi
EOF
    benchmark_rv=1
}
export UUID=$(uuidgen | head -c8)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')
echo "############################################"
echo "# Benchmark UUID: ${UUID}"
echo "############################################"

if [[ $PLATFORM == "baremetal" ]]; then
    env >> /tmp/environment.txt
    run_baremetal_benchmark
else
    setup
    if [[ -n ${workload} ]]; then
        echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
        git clone -q -b ${E2E_BENCHMARKING_BRANCH} ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
        cd /home/airflow/workspace/e2e-benchmarking/workloads/$workload
    fi
    
    echo "Running: ${command}"
    eval $command
    benchmark_rv=$?
fi
echo $UUID
exit $benchmark_rv
