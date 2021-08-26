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
    export PATH=$PATH:/usr/bin
    export AWS_REGION=us-west-2
    export AWS_ACCESS_KEY_ID=$(cat ${json_file} | jq -r .aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat ${json_file} | jq -r .aws_secret_access_key)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export OCM_ENVIRONMENT=$(cat ${json_file} | jq -r .ocm_environment)
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    rosa login --env=${ROSA_ENVIRONMENT}
}

install(){
    cat << EOF > /home/airflow/workspace/config.yaml
cloudProvider:
  providerId: aws
  region: ${AWS_REGION}
cluster:
  multiAZ: true
  name: ${CLUSTER_NAME}
ocm:
  token: "${ROSA_TOKEN}"
  expiration: ${EXPIRATION_TIME}
rosa:
  awsAccessKey: ${AWS_ACCESS_KEY_ID}
  awsSecretAccessKey: ${AWS_SECRET_ACCESS_KEY}
  awsRegion: ${AWS_REGION}
  env: ${OCM_ENVIRONMENT}
  computeNodes: ${COMPUTE_WORKERS_NUMBER}
  computeMachineType: ${COMPUTE_WORKERS_TYPE}
provider: rosa
EOF
    cat /home/airflow/workspace/config.yaml
    if [ ${NETWORK_TYPE} == "OVNKubernetes" ] ; then
    	export JOB_TYPE=periodic && export CLUSTER_NETWORK_PROVIDER=OVNKubernetes && export INSTALL_LATEST_NIGHTLY=${version} && /usr/local/bin/osde2e test --custom-config config.yaml --must-gather=false
    else
        export INSTALL_LATEST_NIGHTLY=${version} && /usr/local/bin/osde2e test --custom-config config.yaml --must-gather=false
    fi
    postinstall
}

postinstall(){
    _download_kubeconfig $(_get_cluster_id ${CLUSTER_NAME}) ./kubeconfig
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
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
