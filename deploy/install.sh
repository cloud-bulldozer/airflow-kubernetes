#!/bin/bash
set -x 
usage() { printf "Usage: ./install.sh -u USER -b BRANCH \nUser/Branch should point to your fork of the airflow-kubernetes repository" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
while getopts b:u:c: flag
do
    case "${flag}" in
        u) user=${OPTARG};;
        b) branch=${OPTARG};;
        c) cluster_name=${OPTARG};;
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

install_yq(){
    YQ_VERSION=3.4.1
    YQ_BINARY=yq_linux_amd64
    wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY} -O /usr/bin/yq &&\
        chmod +x /usr/bin/yq
}

add_privileged_service_accounts(){
    oc -n airflow adm policy add-scc-to-user privileged -z airflow-scheduler 
    oc -n airflow adm policy add-scc-to-user privileged -z airflow-webserver
    oc -n airflow adm policy add-scc-to-user privileged -z airflow-worker
    oc -n airflow adm policy add-scc-to-user privileged -z builder
    oc -n airflow adm policy add-scc-to-user privileged -z deployer
    oc -n airflow adm policy add-scc-to-user privileged -z default
}

install_airflow_workaround(){
    git clone https://github.com/whitleykeith/airflow-kubernetes 
    cd airflow-kubernetes/airflow
    helm dep update
    
    helm upgrade airflow . --namespace airflow --install
}

install_argo(){    
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
}

create_namespaces(){
    kubectl create namespace argocd || true
    kubectl create namespace airflow || true
}

create_airflow_app(){
    cat $GIT_ROOT/apps/airflow/airflow.yaml | \
    yq w - 'spec.source.helm.parameters.(name==dags.gitSync.repo).value' https://github.com/$user/airflow-kubernetes.git | \
    yq w - 'spec.source.helm.parameters.(name==dags.gitSync.branch).value' $branch | \
    kubectl apply -f -
}

create_routes(){
    airflow_route="airflow-k8.apps.$cluster_name.perfscale.devcluster.openshift.com"
    argo_route="argo.apps.$cluster_name.perfscale.devcluster.openshift.com"

    cat $GIT_ROOT/apps/airflow/route.yaml | \
    yq w - 'spec.host' $airflow_route | \
    kubectl apply -f -

    echo "Airflow route configured at $airflow_route"

    cat $GIT_ROOT/apps/argocd/route.yaml | \
    yq w - 'spec.host' $argo_route | \
    kubectl apply -f -

    echo "Argo route configured at $argo_route"
}

remove_airflow_workaround(){
    helm delete airflow -n airflow
}


install_helm
install_yq
create_namespaces
add_privileged_service_accounts
install_airflow_workaround
install_argo
create_airflow_app
create_routes










argo_route=$(oc get routes -n argocd -o json | jq -r '.items[0].spec.host')
airflow_route=$(oc get routes -n airflow -o json | jq -r '.items[0].spec.host')

echo "Argo is setting up your Cluster, check the status here: $argo_route"
echo "Airflow will be at $airflow_route, user/pass is admin/admin"


