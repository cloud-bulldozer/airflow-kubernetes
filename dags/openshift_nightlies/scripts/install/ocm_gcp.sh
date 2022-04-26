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
    echo $(ocm list clusters --no-headers --columns id $1)
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    echo $(ocm list clusters --no-headers --columns state $1)
}

_wait_for_cluster_ready(){
    echo "INFO: Waiting about 1 hour for cluster on ready status"
    # 180 iterations, sleeping 60 seconds, 3 hours of wait
    for i in `seq 1 180` ; do
	CLUSTER_STATUS=$(_get_cluster_status $1)
	if [ ${CLUSTER_STATUS} == "ready" ] ; then
            sleep 60 # Wait 60 seconds to allow OCM to really finish the cluster installation
	    return 0
	else
	    echo "INFO: ${i}/60. Cluster on ${CLUSTER_STATUS} status, waiting 60 seconds for next check"
	    sleep 60
	fi
    done
    echo "ERROR: Cluster $1 not installed after 3 hours"
    exit 1
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export GCP_REGION=us-east4
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    echo ${GCP_MANAGED_SERVICES_TOKEN} > ./serviceAccount.json
    export CLOUDSDK_PYTHON=python3.9
    export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
    if [[ ${OCM_CLI_VERSION} == "master" ]]; then
        git clone --depth=1 --single-branch --branch main https://github.com/openshift-online/ocm-cli
        pushd ocm-cli
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd
    fi
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    gcloud config set account osd-ccs-admin@openshift-perfscale.iam.gserviceaccount.com
    gcloud auth activate-service-account osd-ccs-admin@openshift-perfscale.iam.gserviceaccount.com --key-file ./serviceAccount.json
    gcloud config set project openshift-perfscale
}

install(){
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export OCM_VERSION=$(ocm list versions --channel-group nightly | grep ^${version} | sort -rV | head -1)
    [ -z ${OCM_VERSION} ] && echo "ERROR: Image not found for version (${version}) on OCM Nightly channel group" && exit 1
    ocm create cluster --ccs --provider gcp --region ${GCP_REGION} --service-account-file ./serviceAccount.json --channel-group nightly --version ${OCM_VERSION} --multi-az --compute-nodes ${COMPUTE_WORKERS_NUMBER} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --network-type ${NETWORK_TYPE} ${CLUSTER_NAME}
    _wait_for_cluster_ready ${CLUSTER_NAME}
    postinstall
}

postinstall(){
    export WORKLOAD_TYPE=$(cat ${json_file} | jq -r .openshift_workload_node_instance_type)
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig $(_get_cluster_id ${CLUSTER_NAME}) ./kubeconfig
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    export PASSWORD=$(echo airflow-49-de9d | md5sum | awk '{print $1}')
    ocm create idp -n localauth -t htpasswd --username kubeadmin --password ${PASSWORD} -c ${CLUSTER_NAME}
    ocm create user kubeadmin -c $(_get_cluster_id ${CLUSTER_NAME}) --group=cluster-admins

    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    # create machinepool for workload nodes
    ocm create machinepool -c ${CLUSTER_NAME} --instance-type ${WORKLOAD_TYPE} --labels 'node-role.kubernetes.io/workload=' --taints 'role=workload:NoSchedule' --replicas 3 workload
    # set expiration time
    EXPIRATION_STRING=$(date -d "${EXPIRATION_TIME}" '+{"expiration_timestamp": "%FT%TZ"}')
    ocm patch /api/clusters_mgmt/v1/clusters/$(_get_cluster_id ${CLUSTER_NAME}) <<< ${EXPIRATION_STRING}
    # Add firewall rules
    NETWORK_NAME=$(gcloud compute networks list --format="value(name)" | grep ^${CLUSTER_NAME})
    gcloud compute firewall-rules create ${NETWORK_NAME}-icmp --network ${NETWORK_NAME} --priority 101 --description 'scale-ci allow icmp' --allow icmp
    gcloud compute firewall-rules create ${NETWORK_NAME}-ssh --network ${NETWORK_NAME} --direction INGRESS --priority 102 --description 'scale-ci allow ssh' --allow tcp:22
    gcloud compute firewall-rules create ${NETWORK_NAME}-pbench --network ${NETWORK_NAME} --direction INGRESS --priority 103 --description 'scale-ci allow pbench-agents' --allow tcp:2022
    gcloud compute firewall-rules create ${NETWORK_NAME}-net --network ${NETWORK_NAME} --direction INGRESS --priority 104 --description 'scale-ci allow tcp,udp network tests' --rules tcp:20000-30109,udp:20000-30109 --action allow
    gcloud compute firewall-rules create ${NETWORK_NAME}-hostnet --network ${NETWORK_NAME} --priority 105 --description 'scale-ci allow tcp,udp hostnetwork tests' --rules tcp:32768-60999,udp:32768-60999 --action allow
}

cleanup(){
    ocm delete cluster $(_get_cluster_id ${CLUSTER_NAME})
    ocm logout
}

preclean(){
    echo "Delete old firewall-rules.."
    for i in $(gcloud compute firewall-rules list | grep ${CLUSTER_NAME} | awk '{print$1}'); do 
        gcloud compute firewall-rules delete $i --quiet || true
    done
    echo "Delete old routers.."
    for i in $(gcloud compute routers list | grep ${CLUSTER_NAME} | awk '{print$1}'); do 
        gcloud compute routers delete $i --quiet --region $(gcloud compute routers list | grep $i | awk '{print$2}') || true
    done    
    echo "Delete old routes.."
    for i in $(gcloud compute routes list | grep ${CLUSTER_NAME} | awk '{print$1}'); do 
        gcloud compute routes delete $i --quiet || true
    done
    echo "Delete old networks.."
    for i in $(gcloud compute networks list | grep ${CLUSTER_NAME} | awk '{print$1}'); do 
        gcloud compute networks delete $i --quiet || true
    done
}
cat ${json_file}

setup

if [[ "$operation" == "install" ]]; then
    printf "INFO: Checking if cluster is already installed"
    CLUSTER_STATUS=$(_get_cluster_status ${CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, precleaning & installing..."
        preclean # to cleanup any old orphaned resources from prev itr
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
