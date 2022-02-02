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
    ls ~/
    echo $PWD 
    rm -f ~/.kube/config 

    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc

    export PATH=$PATH:$(pwd)

    oc login -u ${user} -p ${pass} ${url} --insecure-skip-tls-verify
    ls ~/

    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=$pass
}

create_login_secrets