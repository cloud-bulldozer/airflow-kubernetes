#!/bin/bash
set -a

install_argo_cli(){
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
}

output_info() {
    _argo_url=$(oc get route/argocd -o jsonpath='{.spec.host}' -n argocd)
    _argo_user="admin"
    _argo_password=$(kubectl get secret/argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)

    printf "\n\n ArgoCD Configs"
    printf "\n Host: $_argo_url \n User: $_argo_user \n Password: $_argo_password"

    _airflow_url=$(oc get route/airflow -o jsonpath='{.spec.host}' -n airflow)
    _airflow_user="admin"
    _airflow_password="REDACTED"

    printf "\n\n Airflow Configs (Password was user defined so this script doesn't know it!)"
    printf "\n Host: $_airflow_url \n User: $_airflow_user \n Password: $_airflow_password"


    _logging_elastic_url=$(oc get route/logging-elastic -o jsonpath='{.spec.host}' -n openshift-logging)
    _logging_kibana_url=$(oc get route/logging-kibana -o jsonpath='{.spec.host}' -n openshift-logging)
    _logging_elastic_user="elastic"
    _logging_elastic_password=$(kubectl get secret/logging-es-elastic-user -o jsonpath='{.data.elastic}' -n openshift-logging | base64 --decode)

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