#!/bin/bash

set -exo pipefail


while getopts d:e: flag
do
    case "${flag}" in
        d) dag_id=${OPTARG};;
        e) execution_date=${OPTARG};;
    esac
done

setup(){
    # Generate a uuid
    export UUID=$(uuidgen)

    # Elasticsearch and jenkins credentials
    export ES_SERVER=$ES_SERVER
    export ES_INDEX=$ES_INDEX

    # Timestamp
    timestamp=`date +"%Y-%m-%dT%T.%3N"`

    # Get OpenShift cluster details
    cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    masters=$(oc get nodes -l node-role.kubernetes.io/master --no-headers=true | wc -l)
    workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers=true | wc -l)
    workload=$(oc get nodes -l node-role.kubernetes.io/workload --no-headers=true | wc -l)
    infra=$(oc get nodes -l node-role.kubernetes.io/infra --no-headers=true | wc -l)
    all=$(oc get nodes  --no-headers=true | wc -l)
}

get_task_states(){
    task_states=$(airflow tasks states-for-dag-run $dag_id $execution_date -o json)
}

# Defaults
if [[ -z $ES_SERVER ]]; then
  echo "Elastic server is not defined, please check"
  help
  exit 1
fi

if [[ -z $ES_INDEX ]]; then
  export ES_INDEX=perf_scale_ci
fi
if [[ -z $dag_id ]] || [[ -z $execution_date ]]; then
    echo "Dag ID or execution date is missing, exiting"
    exit 1