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

git clone https://github.com/openshift-scale/scale-ci-deploy /home/airflow/
cd scale-ci-deploy
cat /inventory
ANSIBLE_DEBUG=True ansible-playbook -vvvv -i /inventory OCP-$version.X/install-on-$platform.yml --syntax-check --extra-vars ${json_string}