#!/bin/bash

set -x 
usage() { printf "Usage: ./install.sh -u USER -b BRANCH \nUser/Branch should point to your fork of the airflow-kubernetes repository" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
while getopts b:u:c: flag
do
    case "${flag}" in
        u) user=${OPTARG};;
        b) branch=${OPTARG};;
        *) usage;;
    esac
done

if [[ -z "$user" || -z $branch ]]; then 
    usage
fi

install_helm(){
    HELM_VERSION=v3.4.2
    wget https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz
    tar -zxf helm-${HELM_VERSION}-linux-amd64.tar.gz
    mv linux-amd64/helm /usr/bin/helm
    helm repo add stable https://charts.helm.sh/stable/   
}

install_argo(){    
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    cat << EOF | kubectl -n argocd apply -f -
    apiVersion: v1
    data:
      repositories: |
        - type: helm
          url: https://charts.bitnami.com/bitnami
          name: bitnami
    kind: ConfigMap
    metadata:
      labels:
        app.kubernetes.io/name: argocd-cm
        app.kubernetes.io/part-of: argocd
      name: argocd-cm
      namespace: argocd
EOF
}

create_namespaces(){
    kubectl create namespace argocd || true
    kubectl create namespace fluentd || true
    kubectl create namespace airflow || true
    kubectl create namespace logging || true
    kubectl create namespace elastic-system || true
    kubectl create namespace perf-results || true
}

add_privileged_service_accounts(){
    oc adm policy add-scc-to-group privileged system:authenticated
}


install_perfscale(){
    cluster_domain=$(oc get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
    cd $GIT_ROOT/charts/perfscale
    helm upgrade perfscale . --install --namespace argocd --set global.baseDomain=$cluster_domain

}

install_helm
create_namespaces
add_privileged_service_accounts
install_argo
install_perfscale