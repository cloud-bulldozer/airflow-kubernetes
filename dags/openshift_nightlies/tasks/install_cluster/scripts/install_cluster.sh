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

git clone https://github.com/openshift-scale/scale-ci-deploy 
ansible-playbook -v -i /inventory scale-ci-deploy/OCP-$version.X/install-on-$platform.yml"