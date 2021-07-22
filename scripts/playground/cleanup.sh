#!/bin/bash
set -a
usage() { echo "Usage: $0 [-p <string> (airflow password)]" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
source $GIT_ROOT/scripts/common.sh
_remote_origin_url=$(git config --get remote.origin.url)
_remote_user=$(git config --get remote.origin.url | cut -d'/' -f4 | tr '[:upper:]' '[:lower:]')
_raw_branch=$(git branch --show-current)
_branch=$(git branch --show-current | tr '[:upper:]' '[:lower:]' | sed -r 's/[_]+/-/g')
_airflow_namespace=$_remote_user-$_branch-airflow
_cluster_domain=$(kubectl get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}')



envsubst < $GIT_ROOT/scripts/playground/templates/airflow.yaml | kubectl delete -f -
oc delete project/$_airflow_namespace || true
