#!/bin/bash
while getopts p:t:s:x: flag
do
    case "${flag}" in
        p) platform=${OPTARG};;
        t) version=${OPTARG};;
        j) json_string=${OPTARG};;
    esac
done

git clone https://github.com/openshift-scale/scale-ci-deploy 
ansible-playbook -v -i ../files/inventory scale-ci-deploy/OCP-$version.X/install-on-$platform.yml --extra-vars "${json_string}"