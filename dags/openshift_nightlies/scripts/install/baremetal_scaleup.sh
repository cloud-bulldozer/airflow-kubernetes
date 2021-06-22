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
    # Clone JetSki playbook
    git clone --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/JetSki.git /tmp/JetSki
    pushd /tmp/JetSki

    # Clone Perf private keys
    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    export ANSIBLE_FORCE_COLOR=true
    chmod 600 ${PRIVATE_KEY}

    pushd ansible-ipi-install

}

run_ansible_playbook(){
    time /home/airflow/.local/bin/ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
}

echo "Staring to scaleup cluster..." 
date
echo "-------------------------------"
setup
run_ansible_playbook
echo "Finished cluster scaleup"
date
echo "-------------------------------"

