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
    if [ ${ROUTABLE_API} == true ]
    then
        sed -i "/^extcidrnet/c extcidrnet=\"${BAREMETAL_NETWORK_CIDR}\"" inventory/jetski/hosts
        sed -i "/^cluster_random=/c cluster_random=false" inventory/jetski/hosts
        sed -i "/^cluster=/c cluster=\"${BAREMETAL_NETWORK_VLAN}\"" inventory/jetski/hosts
        sed -i "/^domain=/c domain=\"${OPENSHIFT_BASE_DOMAIN}\"" inventory/jetski/hosts
    fi
}

run_ansible_playbook(){
    time /home/airflow/.local/bin/ansible-playbook -i inventory/jetski/hosts playbook-jetski.yml --extra-vars "@${json_file}"
}

echo "Staring cluster installation..." 
date
echo "-------------------------------"
setup
run_ansible_playbook
echo "Finished cluster installation" 
date
echo "-------------------------------"

