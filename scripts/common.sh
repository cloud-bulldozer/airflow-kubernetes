#!/bin/bash
set -a

_remote_origin_url=$(git config --get remote.origin.url | sed -e 's,git@github.com:,https://github.com/,g')
_remote_user=$( echo $_remote_origin_url | cut -d'/' -f4 | tr '[:upper:]' '[:lower:]')
_cluster_domain=$(kubectl get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
_branch=$(git branch --show-current)
_branch_display_name=$(git branch --show-current | tr '[:upper:]' '[:lower:]' | sed -r 's/[_]+/-/g')

echo -e "Remote Origin:  \t $_remote_origin_url"
echo -e "Branch: \t         $_branch"

install_argo_cli(){
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
}

install_helm(){
    HELM_VERSION=v3.4.2
    wget https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz
    tar -zxf helm-${HELM_VERSION}-linux-amd64.tar.gz
    mv linux-amd64/helm /usr/bin/helm
    helm repo add stable https://charts.helm.sh/stable/   
}



output_info() {
    _airflow_ns=${_airflow_namespace:-airflow}
    _argo_url=$(oc get route/argocd-server -o jsonpath='{.spec.host}' -n argocd)
    _argo_user="admin"
    _argo_password=$(kubectl get secret/argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)

    printf "\n\n ArgoCD Configs"
    printf "\n Host: https://$_argo_url \n User: $_argo_user \n Password: $_argo_password"

    _airflow_url=$(oc get route/airflow -o jsonpath='{.spec.host}' -n $_airflow_ns)
    _airflow_user="admin"
    _airflow_password="REDACTED"

    printf "\n\n Airflow Configs (Password was user defined so this script doesn't know it!)"
    printf "\n Host: https://$_airflow_url \n User: $_airflow_user \n Password: $_airflow_password\n\n"

    _results_dashboard_url=$(oc get route/perf-dashboard -o jsonpath='{.spec.host}' -n dashboard)
    if [ -z "$_results_dashboard_url" ]; then
        printf "Dashboard is not present\n\n"
    else
        _results_api_url=$(oc get route/perf-dashboard-api -o jsonpath='{.spec.host}' -n dashboard)

        printf "\n\n Results Dashboard Configs"
        printf "\n Dashboard URL: http://$_results_dashboard_url \n API Endpoint: http://$_results_api_url \n"
    fi

}
