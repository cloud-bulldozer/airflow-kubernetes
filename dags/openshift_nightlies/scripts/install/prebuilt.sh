#!/bin/bash
set -ex

while getopts u:p:w: flag
do
    case "${flag}" in
        u) user=${OPTARG};;
        p) pass=${OPTARG};;
        w) url=${OPTARG};;
    esac
done

create_login_secrets(){
    echo ${user}; echo ${pass}; echo ${url};
    ls ~/.kube/
    rm -f ~/.kube/config 

    oc login -u ${user} -p ${pass} ${url}
    ls ~/.kube/
}

