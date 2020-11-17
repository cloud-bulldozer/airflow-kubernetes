#!/bin/bash

echo "Hello!"

while getopts p:v:j: flag
do
    case "${flag}" in
        p) platform=${OPTARG};;
        v) version=${OPTARG};;
        j) json_string=${OPTARG};;
    esac
done



cd /home/airflow
git clone https://github.com/openshift-scale/scale-ci-deploy
git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
export PUBLIC_KEY=perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
export PRIVATE_KEY=perf-dept/ssh_keys/id_rsa_pbench_ec2
chmod 600 ${PRIVATE_KEY}

# Create inventory File:
echo "[orchestration]" > inventory
echo "${ORCHESTRATION_HOST}" >> inventory

cat inventory
ANSIBLE_DEBUG=True ansible-playbook -vvvv -i inventory OCP-$version.X/install-on-$platform.yml --extra-vars ${json_string}