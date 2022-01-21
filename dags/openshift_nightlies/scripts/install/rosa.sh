#!/bin/bash

set -ex

while getopts v:a:j:o: flag
do
    case "${flag}" in
        v) version=${OPTARG};;
        j) json_file=${OPTARG};;
        o) operation=${OPTARG};;
        *) echo "ERROR: invalid parameter ${flag}" ;;
    esac
done

_get_cluster_id(){
    echo $(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .id')
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    echo $(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .status.state')
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export AWS_REGION=us-west-2
    export AWS_ACCESS_KEY_ID=$(cat ${json_file} | jq -r .aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat ${json_file} | jq -r .aws_secret_access_key)
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export ROSA_CLI_VERSION=$(cat ${json_file} | jq -r .rosa_cli_version)
    if [[ ${ROSA_CLI_VERSION} == "master" ]]; then
        git clone https://github.com/openshift/rosa
	pushd rosa
	make
	sudo mv rosa /usr/local/bin/
	popd
    fi
    rosa login --env=${ROSA_ENVIRONMENT}
    rosa whoami
    rosa verify quota
    rosa verify permissions
}

install(){
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export ROSA_VERSION=$(rosa list versions -o json --channel-group=nightly | jq -r '.[] | select(.raw_id|startswith('\"${version}\"')) | .raw_id' | sort -rV | head -1)
    [ -z ${ROSA_VERSION} ] && echo "ERROR: Image not found for version (${version}) on ROSA Nightly channel group" && exit 1
    rosa create cluster --cluster-name ${CLUSTER_NAME} --version "${ROSA_VERSION}-nightly" --channel-group=nightly --multi-az --compute-machine-type ${COMPUTE_WORKERS_TYPE} --compute-nodes ${COMPUTE_WORKERS_NUMBER} --network-type ${NETWORK_TYPE} --watch
    postinstall
}

postinstall(){
    export WORKLOAD_TYPE=$(cat ${json_file} | jq -r .openshift_workload_node_instance_type)
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig $(_get_cluster_id ${CLUSTER_NAME}) ./kubeconfig
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    PASSWORD=$(rosa create admin -c $(_get_cluster_id ${CLUSTER_NAME}) -y 2>/dev/null | grep "oc login" | awk '{print $7}')
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    # create machinepool for workload nodes
    rosa create machinepool -c ${CLUSTER_NAME} --instance-type ${WORKLOAD_TYPE} --name workload --labels node-role.kubernetes.io/workload= --taints role=workload:NoSchedule --replicas 3
    # set expiration to 24h
    rosa edit cluster -c $(_get_cluster_id ${CLUSTER_NAME}) --expiration=${EXPIRATION_TIME}
}

cleanup(){
    ROSA_CLUSTER_ID=$(_get_cluster_id ${CLUSTER_NAME})
    rosa delete cluster -c ${ROSA_CLUSTER_ID} -y
    rosa logout
}

cat ${json_file}

setup

if [[ "$operation" == "install" ]]; then
    printf "INFO: Checking if cluster is already installed"
    CLUSTER_STATUS=$(_get_cluster_status ${CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, installing..."
        install
    elif [ "${CLUSTER_STATUS}" == "ready" ] ; then
        printf "INFO: Cluster ${CLUSTER_NAME} already installed and ready, reusing..."
	postinstall
    else
        printf "INFO: Cluster ${CLUSTER_NAME} already installed but not ready, exiting..."
	exit 1
    fi

elif [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
    cleanup
fi
