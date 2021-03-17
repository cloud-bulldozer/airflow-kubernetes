#!/bin/bash
 
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

install_argo_cli(){
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
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

wait_for_apps_to_be_healthy(){
    argocd login $(oc get route/argocd -o jsonpath='{.spec.host}' -n argocd) --username admin --password $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[].metadata.name}') --insecure
    argocd app wait -l app.kubernetes.io/managed-by=Helm
}

output_info() {
    _argo_url=$(oc get route/argocd -o jsonpath='{.spec.host}' -n argocd)
    _argo_user="admin"
    _argo_password=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[].metadata.name}')

    printf "\n\n ArgoCD Configs"
    printf "\n Host: $_argo_url \n User: $_argo_user \n Password: $_argo_password"

    _airflow_url=$(oc get route/airflow -o jsonpath='{.spec.host}' -n airflow)
    _airflow_user="admin"
    _airflow_password="admin"

    printf "\n\n Airflow Configs"
    printf "\n Host: $_airflow_url \n User: $_airflow_user \n Password: $_airflow_password"


    _logging_elastic_url=$(oc get route/logging-elastic -o jsonpath='{.spec.host}' -n logging)
    _logging_kibana_url=$(oc get route/logging-kibana -o jsonpath='{.spec.host}' -n logging)
    _logging_elastic_user="elastic"
    _logging_elastic_password=$(kubectl get secret/logging-es-elastic-user -o jsonpath='{.data.elastic}' -n logging | base64 --decode)

    printf "\n\n Logging Elasticsearch Configs"
    printf "\n Elastic Host: $_logging_elastic_url \n Kibana Host: $_logging_kibana_url \n User: $_logging_elastic_user \n Password: $_logging_elastic_password"

    _results_elastic_url=$(oc get route/perf-results-elastic -o jsonpath='{.spec.host}' -n perf-results)
    _results_kibana_url=$(oc get route/perf-results-kibana -o jsonpath='{.spec.host}' -n perf-results)
    _results_elastic_user="elastic"
    _results_elastic_password=$(kubectl get secret/perf-results-es-elastic-user -o jsonpath='{.data.elastic}' -n perf-results | base64 --decode)

    printf "\n\n Results Elasticsearch Configs"
    printf "\n Elastic Host: $_results_elastic_url \n Kibana Host: $_results_kibana_url \n User: $_results_elastic_user \n Password: $_results_elastic_password"

    _results_dashboard_url=$(oc get route/perf-dashboard -o jsonpath='{.spec.host}' -n perf-results)
    _results_api_url=$(oc get route/perf-dashboard-api -o jsonpath='{.spec.host}' -n perf-results)

    printf "\n\n Results Dashboard Configs"
    printf "\n Dashboard URL: $_results_dashboard_url \n API Endpoint: $_results_api_url \n"

}

echo "Installing Dependencies"
install_argo_cli > /dev/null 2>&1
install_helm > /dev/null 2>&1
echo "Creating Namespaces if they don't exist..."
create_namespaces > /dev/null 2>&1
echo "Creating services accounts"
add_privileged_service_accounts > /dev/null 2>&1
echo "Installing Argo"
install_argo > /dev/null
sleep 60
echo "Installing PerfScale Platform"
install_perfscale
echo "PerfScale Platform Creating, waiting for Applications to become healthy"
wait_for_apps_to_be_healthy
output_info