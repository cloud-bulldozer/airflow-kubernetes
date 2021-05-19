#!/bin/bash

set -ex
export DISABLE_PODMAN=true

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
    # Clone webfuse
    git clone --single-branch --branch main https://${SSHKEY_TOKEN}@github.com/redhat-performance/webfuse.git /tmp/webfuse
    pushd /tmp/webfuse

    # Clone Perf private keys
    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/tmp/webfuse/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/webfuse/perf-dept/ssh_keys/id_rsa_pbench_ec2
    export ANSIBLE_FORCE_COLOR=true
    chmod 600 ${PRIVATE_KEY}

    pushd ansible
    # Create inventory file
    echo "[orchestration]" > hosts
    echo "${ORCHESTRATION_HOST}   ansible_user=${ORCHESTRATION_USER}   ansible_ssh_private_key_file=${PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> hosts

    cp group_vars/all.yml.sample group_vars/all.yml

}

run_ansible_playbook(){
    if [ -z ${WEBFUSE_SKIPTAGS} ]; then
        time ansible-playbook -i hosts ${WEBFUSE_PLAYBOOK} --extra-vars "@${json_file}"
    else
        time ansible-playbook -i hosts ${WEBFUSE_PLAYBOOK} --skip-tags ${WEBFUSE_SKIPTAGS} --extra-vars "@${json_file}"
    fi

}

echo "Staring to scaleup cluster..." 
date
echo "-------------------------------"
setup
run_ansible_playbook
echo "Finished cluster scaleup"
date
echo "-------------------------------"

