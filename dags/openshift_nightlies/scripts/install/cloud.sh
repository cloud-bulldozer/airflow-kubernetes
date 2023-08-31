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
    git clone --depth=1 --single-branch --branch master https://github.com/cloud-bulldozer/scale-ci-deploy
    git clone --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    export AWS_REGION=${AWS_REGION:-us-west-2}
    export AWS_SHARED_CREDENTIALS_FILE="/root/$DEPLOY_PATH/credentials"
    chmod 600 ${PRIVATE_KEY}


    cd scale-ci-deploy
    # Create inventory File:
    echo "[orchestration]" > inventory
    echo "${ORCHESTRATION_HOST}" >> inventory
    cat inventory

    sed -i 's/timeout = 30/timeout = 60/g' ansible.cfg
    echo "retries = 3" >> ansible.cfg
    echo "control_path = /tmp/ansible-ssh-%%h-%%p-%%r" >> ansible.cfg
    echo "ssh_args = -o ServerAliveInterval=30" >> ansible.cfg
    cat ansible.cfg

}

run_ansible_playbook(){
    /home/airflow/.local/bin/ansible-playbook -vv -i inventory OCP-4.X/deploy-cluster.yml -e platform="$platform" --extra-vars "@${json_file}"
}

post_install(){
    ssh ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat /root/$DEPLOY_PATH/.openshift_install.log"
    printenv

    _kubeadmin_password=$(ssh ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat /root/$DEPLOY_PATH/auth/kubeadmin-password")

    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=$_kubeadmin_password
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=/home/airflow/workspace/scale-ci-deploy/OCP-4.X/kubeconfig
}

cleanup(){
    kubectl delete secret ${KUBEADMIN_NAME} || true
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
fi


