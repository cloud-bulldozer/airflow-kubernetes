#!/bin/bash

set -exo pipefail

export dag_id=${AIRFLOW_CTX_DAG_ID}
export execution_date=${AIRFLOW_CTX_EXECUTION_DATE}
export dag_run_id=${AIRFLOW_CTX_DAG_RUN_ID}
export ci="AIRFLOW"
printenv

# Get Airflow URL
export airflow_base_url="http://$(kubectl get route/airflow -n airflow -o jsonpath='{.spec.host}')"

setup(){
    # Generate a uuid
    export UUID=${UUID:-$(uuidgen)}

    # Elasticsearch Config
    export ES_SERVER=$ES_SERVER
    export ES_INDEX=$ES_INDEX

    # Timestamp
    timestamp=`date +"%Y-%m-%dT%T.%3N"`

    # Setup Kubeconfig
    export KUBECONFIG=/home/airflow/auth/config
    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc
    export PATH=$PATH:/home/airflow/.local/bin:$(pwd)
    # Get OpenShift cluster details
    cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}') || echo "Cluster Install Failed"
    cluster_version=$(oc version -o json | jq -r '.openshiftVersion') || echo "Cluster Install Failed"
    network_type=$(oc get network.config/cluster -o jsonpath='{.status.networkType}') || echo "Cluster Install Failed"
    platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}') || echo "Cluster Install Failed"
    masters=$(oc get nodes -l node-role.kubernetes.io/master --no-headers=true | wc -l) || true
    workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers=true | wc -l) || true
    infra=$(oc get nodes -l node-role.kubernetes.io/infra --no-headers=true | wc -l) || true
    worker_type=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[].metadata.labels.beta\.kubernetes\.io/instance-type}') || true
    infra_type=$(oc get nodes -l node-role.kubernetes.io/infra -o jsonpath='{.items[].metadata.labels.beta\.kubernetes\.io/instance-type}') || true
    master_type=$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[].metadata.labels.beta\.kubernetes\.io/instance-type}') || true
    all=$(oc get nodes  --no-headers=true | wc -l) || true
    # ReleaseStream is piped in via environment variables
    release_stream=${RELEASE_STREAM}
}

index_task(){
    task_json=$1

    state=$(echo $task_json | jq -r '.state')
    task_id=$(echo $task_json | jq -r '.task_id')

    if [[ $task_id == "$AIRFLOW_CTX_TASK_ID" || $task_id == "cleanup" ]]; then
        echo "Index Task doesn't index itself or cleanup step, skipping."
    else
        start_date=$(echo $task_json | jq -r '.start_date')
        end_date=$(echo $task_json | jq -r '.end_date')

        if [[ -z $start_date ]]; then
            start_date=$end_date
        fi

        if [[ -z $start_date || -z $end_date ]]; then
            duration=0
        else
            end_ts=$(date -d $end_date +%s)
            start_ts=$(date -d $start_date +%s)
            duration=$(( $end_ts - $start_ts ))
        fi

        encoded_execution_date=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input()))" <<< "$execution_date")
        build_url="${airflow_base_url}/task?dag_id=${dag_id}&task_id=${task_id}&execution_date=${encoded_execution_date}"

        curl --insecure -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
            "ci_system" : "'$ci'",
            "uuid" : "'$UUID'",
            "release_stream": "'$RELEASE_STREAM'",
            "platform": "'$platform'",
            "master_count": '$masters',
            "worker_count": '$workers',
            "infra_count": '$infra',
            "master_type": "'$master_type'",
            "worker_type": "'$worker_type'",
            "infra_type": "'$infra_type'",
            "total_count": '$all',
            "cluster_name": "'$cluster_name'",
            "cluster_version": "'$cluster_version'",
            "network_type": "'$network_type'",
            "build_tag": "'$task_id'",
            "node_name": "'$HOSTNAME'",
            "job_status": "'$state'",
            "build_url": "'$build_url'",
            "upstream_job": "'$dag_id'",
            "upstream_job_build": "'$dag_run_id'",
            "execution_date": "'$execution_date'",
            "job_duration": "'$duration'",
            "start_date": "'$start_date'",
            "end_date": "'$end_date'",
            "timestamp": "'$start_date'"
            }' $ES_SERVER/$ES_INDEX/_doc/$dag_id%2F$dag_run_id%2F$task_id

    fi

}


index_tasks(){

    task_states=$(AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR  airflow tasks states-for-dag-run $dag_id $execution_date -o json)
    task_json=$( echo $task_states | jq -c ".[] | select( .task_id == \"$TASK\")")
    index_task $task_json

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

setup
index_tasks
