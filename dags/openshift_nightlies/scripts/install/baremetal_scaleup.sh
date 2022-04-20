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
    git clone --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/JetSki.git /tmp/JetSki
    pushd /tmp/JetSki

    # Clone Perf private keys
    git clone --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    export PUBLIC_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/JetSki/perf-dept/ssh_keys/id_rsa_pbench_ec2 
    export ANSIBLE_FORCE_COLOR=true
    chmod 600 ${PRIVATE_KEY}

    pushd ansible-ipi-install

}

run_ansible_playbook(){
    start=$((CURRENT_WORKER_COUNT + SCALE_STEP))
    if [[ ${TARGET_WORKER_COUNT} -gt ${SCALE_STEP} ]]; then
        for itr in `seq ${start} ${SCALE_STEP} ${TARGET_WORKER_COUNT}`
        do
            sed -i "/\"worker_count\":/c \"worker_count\": ${itr}" ${json_file}
            echo "------------------------Scaling $itr workers------------------------"
            if [ -z ${JETSKI_SKIPTAGS} ]; then
                time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
            else
                time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --skip-tags ${JETSKI_SKIPTAGS} --extra-vars "@${json_file}"
            fi
            echo "------------------------Scaled up to $itr workers------------------------"
        done
        if [[ $itr -lt ${TARGET_WORKER_COUNT} ]]; then
            sed -i "/\"worker_count\":/c \"worker_count\": ${TARGET_WORKER_COUNT}" ${json_file}
            echo "------------------------Scaling $itr workers------------------------"
            if [ -z ${JETSKI_SKIPTAGS} ]; then
                time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
            else
                time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --skip-tags ${JETSKI_SKIPTAGS} --extra-vars "@${json_file}"
            fi
            echo "------------------------Scaled up to $itr workers------------------------"
        fi
    else
        if [ -z ${JETSKI_SKIPTAGS} ]; then
            time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --extra-vars "@${json_file}"
        else
            time ansible-playbook -i inventory/jetski/hosts playbook-jetski-scaleup.yml --skip-tags ${JETSKI_SKIPTAGS} --extra-vars "@${json_file}"
        fi
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

