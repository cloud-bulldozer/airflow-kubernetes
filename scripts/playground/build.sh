#!/bin/bash
set -a
usage() { echo "Usage: $0 [-p <string> (airflow password)]" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
source $GIT_ROOT/scripts/common.sh
_remote_origin_url=$(git config --get remote.origin.url)
_remote_user=$(git config --get remote.origin.url | cut -d'/' -f4 | tr '[:upper:]' '[:lower:]')
_airflow_namespace=$_remote_user-airflow
_branch=$(git branch --show-current)
_cluster_domain=$(oc get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}')


while getopts p: flag
do
    case "${flag}" in
        p) password=${OPTARG};;
        *) usage;;
    esac
done

if [[ -z "$password" ]]; then 
    usage
fi


kubectl create namespace $_airflow_namespace || true
envsubst < $GIT_ROOT/scripts/playground/templates/airflow.yaml | kubectl apply -f -
