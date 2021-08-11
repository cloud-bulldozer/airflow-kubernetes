#!/bin/bash
set -a
usage() { echo "Usage: $0 [-p <string> (airflow password)]" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
source $GIT_ROOT/scripts/common.sh
_airflow_namespace=$_remote_user-airflow


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

echo -e "Release Name:    \t $_airflow_namespace"
echo -e "Airflow Namespace: \t $_airflow_namespace"

oc new-project $_airflow_namespace || true
oc label namespace $_airflow_namespace playground=true || true
envsubst < $GIT_ROOT/scripts/tenant/templates/airflow.yaml | kubectl apply -f -
output_info