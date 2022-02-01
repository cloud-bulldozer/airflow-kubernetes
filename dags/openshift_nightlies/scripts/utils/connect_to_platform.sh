#!/bin/bash
set -eux
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

generate_external_labels(){
    # Get OpenShift cluster details
    export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export OPENSHIFT_VERSION=$(oc version -o json | jq -r '.openshiftVersion')
    export NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.status.networkType}')
    export PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    export DAG_ID=${AIRFLOW_CTX_DAG_ID}

}


install_grafana_agent(){
    envsubst < $SCRIPT_DIR/templates/grafana-agent.yaml | kubectl apply -f -
}

install_promtail(){
    helm repo add grafana https://grafana.github.io/helm-charts 
    helm repo update
    oc create namespace loki || true
    oc adm policy add-scc-to-group privileged system:authenticated
    envsubst < $SCRIPT_DIR/templates/promtail-values.yaml | helm upgrade --install promtail --namespace=loki grafana/promtail -f - 
}


setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    cp /home/airflow/auth/config /home/airflow/workspace/config
    export KUBECONFIG=/home/airflow/workspace/config
    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc
    export PATH=$PATH:$(pwd)

}


setup
generate_external_labels
install_grafana_agent


