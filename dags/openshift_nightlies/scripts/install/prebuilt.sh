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
    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc
    export PATH=$PATH:$(pwd)
    
    mkdir workspace
    cd workspace 
    export KUBECONFIG=kubeconfig
    oc login -u ${user} -p ${pass} ${url} --insecure-skip-tls-verify
    
    unset KUBECONFIG
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=$pass
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=kubeconfig
    cd .. 
}

cleanup(){
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl delete secret ${KUBECONFIG_NAME} || true
}

cleanup
create_login_secrets