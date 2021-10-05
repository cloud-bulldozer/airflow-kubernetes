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
    scale_step=40
    start=$((CURRENT_WORKER_COUNT + scale_step))
    if [[ ${TARGET_WORKER_COUNT} -gt $scale_step ]]; then
        for itr in `seq ${start} ${scale_step} ${TARGET_WORKER_COUNT}`
        do
            sed -i "/\"worker_count\":/c \"worker_count\": ${itr}" ${json_file}
            echo "------------------------Scaling $itr workers------------------------"
            time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
            echo "------------------------Scaled up to $itr workers------------------------"
        done
        if [[ $itr -lt ${TARGET_WORKER_COUNT} ]]; then
            sed -i "/\"worker_count\":/c \"worker_count\": ${itr}" ${json_file}
            echo "------------------------Scaling $itr workers------------------------"
            time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
            echo "------------------------Scaled up to $itr workers------------------------"
        fi
    else
        time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
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

