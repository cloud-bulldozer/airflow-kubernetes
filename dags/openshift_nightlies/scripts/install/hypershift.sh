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
    export HOSTED_KUBECONFIG_NAME=$(echo $KUBECONFIG_NAME | awk -F-kubeconfig '{print$1}')-$HOSTED_NAME-kubeconfig
    export HOSTED_KUBEADMIN_NAME=$(echo $KUBEADMIN_NAME | awk -F-kubeadmin '{print$1}')-$HOSTED_NAME-kubeadmin    
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
}

install(){
    echo "Install Hypershift Operator"
    # aws s3api delete-bucket --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --region $AWS_REGION || true
    aws s3api create-bucket --acl public-read --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION || true
    sleep 10 # wait a few seconds 
    hypershift install --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org --oidc-storage-provider-s3-credentials aws_credentials --oidc-storage-provider-s3-region $AWS_REGION  --enable-ocp-cluster-monitoring
    echo "Create Hosted cluster.."    
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_instance_type)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_network_type)
    export REPLICA_TYPE=$(cat ${json_file} | jq -r .hosted_control_plane_availability)   
    BASEDOMAIN=$(_get_base_domain $(_get_cluster_id ${MGMT_CLUSTER_NAME}))
    echo $PULL_SECRET > pull-secret
    hypershift create cluster aws --name $HOSTED_CLUSTER_NAME --node-pool-replicas=$COMPUTE_WORKERS_NUMBER --base-domain $BASEDOMAIN --pull-secret pull-secret --aws-creds aws_credentials --region $AWS_REGION --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE
    sleep 10 # pause for few sec 
    kubectl get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    echo "Wait till hosted cluster is ready.."
    kubectl wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

postinstall(){
    echo "Create Hosted cluster secrets for benchmarks.."
    kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-admin-kubeconfig -o json | jq -r '.data.kubeconfig' | base64 -d > ./kubeconfig
    PASSWORD=$(kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-kubeadmin-password -o json | jq -r '.data.password' | base64 -d)
    unset KUBECONFIG # Unsetting Management cluster kubeconfig, will fall back to Airflow cluster kubeconfig
    kubectl delete secret $HOSTED_KUBECONFIG_NAME $HOSTED_KUBEADMIN_NAME || true
    kubectl create secret generic $HOSTED_KUBECONFIG_NAME --from-file=config=./kubeconfig
    kubectl create secret generic $HOSTED_KUBEADMIN_NAME --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    echo "Wait till Hosted cluster is ready.."
    export KUBECONFIG=./kubeconfig
    node=0
    while [ $node -lt $COMPUTE_WORKERS_NUMBER ]
    do
        node=$(oc get nodes | grep worker | grep -i ready | wc -l)
        echo "Available nodes on cluster - $HOSTED_CLUSTER_NAME ...$node"
        sleep 300
    done
}

cleanup(){
    echo "Delete Hosted cluster.."

    ROSA_CLUSTER_ID=$(_get_cluster_id ${MGMT_CLUSTER_NAME})
    rosa delete cluster -c ${ROSA_CLUSTER_ID} -y
    rosa logout
}

cat ${json_file}

setup

if [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
    cleanup
else
    printf "INFO: Checking if management cluster is installed and ready"
    CLUSTER_STATUS=$(_get_cluster_status ${MGMT_CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, need a Management cluster to be available first"
        exit 1
    elif [ "${CLUSTER_STATUS}" == "ready" ] ; then
        printf "INFO: Cluster ${MGMT_CLUSTER_NAME} already installed and ready, using..."
	    install
        postinstall
    else
        printf "INFO: Cluster ${MGMT_CLUSTER_NAME} already installed but not ready, exiting..."
	    exit 1
    fi
fi

