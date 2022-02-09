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

_get_base_domain(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/ | jq -r '.dns.base_domain'
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin:/opt/airflow/hypershift/bin
    export HOME=/home/airflow
    export AWS_REGION=us-west-2
    export AWS_ACCESS_KEY_ID=$(cat ${json_file} | jq -r .aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat ${json_file} | jq -r .aws_secret_access_key)
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export MGMT_CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export HOSTED_CLUSTER_NAME=$MGMT_CLUSTER_NAME-$HOSTED_NAME
    export KUBECONFIG=/home/airflow/auth/config
    export ROSA_CLI_VERSION=$(cat ${json_file} | jq -r .rosa_cli_version)
    if [[ ${ROSA_CLI_VERSION} == "master" ]]; then
        git clone https://github.com/openshift/rosa
	pushd rosa
	make
	sudo mv rosa /usr/local/bin/
	popd
    fi
    echo [default] >> aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> aws_credentials
    rosa login --env=${ROSA_ENVIRONMENT}
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    rosa whoami
    rosa verify quota
    rosa verify permissions
    echo "MANAGEMENT CLUSTER VERSION:"
    ocm list cluster $MGMT_CLUSTER_NAME
    echo "MANAGEMENT CLUSTER NODES:"
    kubectl get nodes
    echo "Install Hypershift Operator"
    # aws s3api delete-bucket --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --region $AWS_REGION || true
    aws s3api create-bucket --acl public-read --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION || true
    sleep 10 # wait a few seconds 
    hypershift install --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org --oidc-storage-provider-s3-credentials aws_credentials --oidc-storage-provider-s3-region $AWS_REGION  --enable-ocp-cluster-monitoring
}

install(){
    echo "Create Hosted cluster.."    
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_instance_type)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_network_type)    
    BASEDOMAIN=$(_get_base_domain $(_get_cluster_id ${MGMT_CLUSTER_NAME}))
    echo $PULL_SECRET > pull-secret
    hypershift create cluster aws --name $HOSTED_CLUSTER_NAME --node-pool-replicas=$COMPUTE_WORKERS_NUMBER --base-domain $BASEDOMAIN --pull-secret pull-secret --aws-creds aws_credentials --region $AWS_REGION
    kubectl get hostedcluster -n cluster $HOSTED_CLUSTER_NAME
    echo "Wait till hosted cluster is ready.."
    kubectl wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

postinstall(){

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

cat ${json_file}

setup
install

