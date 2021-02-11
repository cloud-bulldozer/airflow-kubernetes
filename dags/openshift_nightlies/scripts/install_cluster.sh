#!/bin/bash

set -ex

while getopts p:v:j:o: flag
do
    case "${flag}" in
        p) platform=${OPTARG};;
        v) version=${OPTARG};;
        j) json_file=${OPTARG};;
        o) operation=${OPTARG};;
    esac
done


setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    git clone https://github.com/whitleykeith/scale-ci-deploy
    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    export ANSIBLE_FORCE_COLOR=true
    export AWS_REGION=us-west-2
    chmod 600 ${PRIVATE_KEY}


    cd scale-ci-deploy
    git checkout airflow-changes
    # Create inventory File:
    echo "[orchestration]" > inventory
    echo "${ORCHESTRATION_HOST}" >> inventory
    cat inventory
    cat ${json_file}

    sed -i 's/timeout = 30/timeout = 60/g' ansible.cfg
    echo "retries = 3" >> ansible.cfg
    echo "control_path = /tmp/ansible-ssh-%%h-%%p-%%r" >> ansible.cfg
    echo "ssh_args = -o ServerAliveInterval=30" >> ansible.cfg
    cat ansible.cfg

}

run_ansible_playbook(){
    ansible-playbook -vv -i inventory OCP-4.X/deploy-cluster.yml -e platform="$platform" --extra-vars "@${json_file}"
}

post_install(){
    ssh ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat /root/scale-ci-$OPENSHIFT_CLUSTER_NAME-$platform/.openshift_install.log"
    printenv
    ls -la /home/airflow/workspace/scale-ci-deploy || true
    ls -la /home/airflow/workspace/scale-ci-deploy/scale-ci-$OPENSHIFT_CLUSTER_NAME-$platform/auth
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=kubeconfig=/home/airflow/workspace/scale-ci-deploy/kubeconfig
}

cleanup(){
    kubectl delete secret ${KUBECONFIG_NAME} || true
}

setup
run_ansible_playbook

if [[ "$operation" == "install" ]]; then
    printf "Running Post Install Steps"
    cleanup
    post_install

elif [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
    cleanup
fi


