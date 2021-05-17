#!/bin/bash

set -ex


setup(){
    # Clone JetSki playbook
    git clone --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/JetSki.git /root/JetSki
    pushd /root/JetSki

    # Clone Perf private keys
    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/root/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/root/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    export ANSIBLE_FORCE_COLOR=true
    chmod 600 ${PRIVATE_KEY}

    # Clone JetSki configs for CI
    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/J-Fleet
    cp J-Fleet/ci/JetSki/group_vars/all.yml ansible-ipi-install/group_vars
    cp J-Fleet/ci/JetSki/inventory/hosts ansible-ipi-install/inventory/jetski/hosts
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
    time ansible-playbook -i inventory/jetski/hosts playbook-jetski.yml
}

setup
run_ansible_playbook

