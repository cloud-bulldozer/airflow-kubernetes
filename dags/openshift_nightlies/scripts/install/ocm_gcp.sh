#!/bin/bash
# shellcheck disable=SC2155
set -ex

export INDEXDATA=()
export exitcode=0

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
    echo "$(ocm get clusters | jq -r '.items[] | select(.display_name == '\"${1}\"') | .id')"
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    echo "$(ocm get clusters | jq -r '.items[] | select(.display_name == '\"${1}\"') | .status.state')"
}

_wait_for_nodes_ready(){
    _download_kubeconfig "$(_get_cluster_id $1)" ./kubeconfig
    export KUBECONFIG=./kubeconfig
    ALL_READY_ITERATIONS=0
    ITERATIONS=0
    # Node count is number of workers + 3 masters + 3 infra
    NODES_COUNT=$(($2+6))
    # 180 seconds per node, waiting 5 times 60 seconds (5*60 = 5 minutes) with all nodes ready to finalize
    while [ ${ITERATIONS} -le ${NODES_COUNT} ] ; do
        NODES_READY_COUNT=$(oc get nodes | grep " Ready " | wc -l)
        if [ ${NODES_READY_COUNT} -ne ${NODES_COUNT} ] ; then
            echo "WARNING: ${ITERATIONS}/${NODES_COUNT} iterations. ${NODES_READY_COUNT}/${NODES_COUNT} nodes ready. Waiting 180 seconds for next check"
            ALL_READY_ITERATIONS=0
            ITERATIONS=$((${ITERATIONS}+1))
            sleep 180
        else
            if [ ${ALL_READY_ITERATIONS} -eq 5 ] ; then
                echo "INFO: ${ALL_READY_ITERATIONS}/5. All nodes ready, continuing process"
                return 0
            else
                echo "INFO: ${ALL_READY_ITERATIONS}/5. All nodes ready. Waiting 60 seconds for next check"
                ALL_READY_ITERATIONS=$((${ALL_READY_ITERATIONS}+1))
                sleep 60
            fi
        fi
    done
    echo "ERROR: Not all nodes (${NODES_READY_COUNT}/${NODES_COUNT}) are ready after about $((${NODES_COUNT}*3)) minutes, dumping oc get nodes..."
    oc get nodes
    return 1
}

_wait_for_cluster_deleted(){
    ITERATIONS=0
    echo "INFO: Waiting 90 iterations until cluster is deleted"
    while [ ${ITERATIONS} -le 90 ] ; do
	CLUSTER_STATUS="$(_get_cluster_status $1)"
	if [ -z "${CLUSTER_STATUS}" ] ; then
            echo "INFO: ${ITERATIONS}/90. Cluster $1 removed."
            return 0
        elif [ ${CLUSTER_STATUS} == "uninstalling" ] ; then
            echo "INFO: ${ITERATIONS}/90. Cluster on ${CLUSTER_STATUS} status, waiting 5 seconds for next check"
            ITERATIONS=$((${ITERATIONS}+1))
            sleep 5
        else
            echo "ERROR: ${ITERATIONS}/90. Failed to delete cluster $1 after 90 loops, exiting..."
            return 1
        fi
    done
}

_wait_for_cluster_ready(){
    START_TIMER=$(date +%s)
    echo "INFO: Installation starts at $(date -d @${START_TIMER})"
    echo "INFO: Waiting about 180 iterations, counting only when cluster enters on installing status"
    ITERATIONS=0
    PREVIOUS_STATUS=""
    # 90 iterations, sleeping 60 seconds, 1.5 hours of wait
    # Only increasing iterations on installing status
    while [ ${ITERATIONS} -le 90 ] ; do
        CLUSTER_STATUS="$(_get_cluster_status $1)"
        CURRENT_TIMER=$(date +%s)
        if [ ${CLUSTER_STATUS} != ${PREVIOUS_STATUS} ] && [ ${PREVIOUS_STATUS} != "" ]; then
            # When detected a status change, index timer and update start time for next status change
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("${PREVIOUS_STATUS}"-"${DURATION}")
            START_TIMER=${CURRENT_TIMER}
            echo "INFO: Cluster status changed to ${CLUSTER_STATUS}"
            if [ ${CLUSTER_STATUS} == "error" ] ; then
                echo "ERROR: Cluster $1 on error state"
                return 1
            fi
        fi
        if [ ${CLUSTER_STATUS} == "ready" ] ; then
            START_TIMER=$(date +%s)
            _wait_for_nodes_ready $1 ${COMPUTE_WORKERS_NUMBER}
	    exitcode=$(($exitcode + $?))
            CURRENT_TIMER=$(date +%s)
            # Time since cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("day2operations-${DURATION}")
            echo "INFO: Cluster and nodes on ready status.."
            return 0
        elif [ ${CLUSTER_STATUS} == "installing" ] ; then
            echo "INFO: ${ITERATIONS}/90. Cluster on ${CLUSTER_STATUS} status, waiting 60 seconds for next check"
            ITERATIONS=$((${ITERATIONS}+1))
            sleep 60
        else
            # Sleep 1 to try to capture as much as posible states before installing
            sleep 1
        fi
        PREVIOUS_STATUS=${CLUSTER_STATUS}
    done
    echo "ERROR: Cluster $1 not installed after 90 iterations, dumping installation logs..."
    return 1
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export GCP_REGION=us-east4
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export MANAGED_OCP_VERSION=$(cat ${json_file} | jq -r .managed_ocp_version)
    export MANAGED_CHANNEL_GROUP=$(cat ${json_file} | jq -r .managed_channel_group)
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export ES_SERVER=$(cat ${json_file} | jq -r .es_server)
    export UUID=$(uuidgen)
    echo ${GCP_MANAGED_SERVICES_TOKEN} > ./serviceAccount.json
    export CLOUDSDK_PYTHON=python3.9
    export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
    if [[ ${OCM_CLI_VERSION} != "container" ]]; then
        OCM_CLI_FORK=$(cat ${json_file} | jq -r .ocm_cli_fork)
        git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
        pushd ocm-cli
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd
    fi
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    ocm whoami
    gcloud config set account osd-ccs-admin@openshift-perfscale.iam.gserviceaccount.com
    gcloud auth activate-service-account osd-ccs-admin@openshift-perfscale.iam.gserviceaccount.com --key-file ./serviceAccount.json
    gcloud config set project openshift-perfscale
    if [ "${MANAGED_OCP_VERSION}" == "latest" ] ; then
        export OCM_VERSION=$(ocm list versions --channel-group=${MANAGED_CHANNEL_GROUP} | grep ^${version} | sort -rV | head -1)
    elif [ "${MANAGED_OCP_VERSION}" == "prelatest" ] ; then
        export OCM_VERSION=$(ocm list versions --channel-group=${MANAGED_CHANNEL_GROUP} | grep ^${version} | sort -rV | head -2 | tail -1)
    else
        export OCM_VERSION=$(ocm list versions --channel-group=${MANAGED_CHANNEL_GROUP} | grep ^${MANAGED_OCP_VERSION}$)
    fi
    [ -z "${OCM_VERSION}" ] && echo "ERROR: Image not found for version (${version}) on OCM ${MANAGED_CHANNEL_GROUP} channel group" && return 1
    return 0

}

install(){
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    ocm create cluster --ccs --provider gcp --region ${GCP_REGION} --service-account-file ./serviceAccount.json --channel-group ${MANAGED_CHANNEL_GROUP} --version ${OCM_VERSION} --multi-az --compute-nodes ${COMPUTE_WORKERS_NUMBER} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --network-type ${NETWORK_TYPE} ${CLUSTER_NAME}
    _wait_for_cluster_ready "${CLUSTER_NAME}"
    exitcode=$(($exitcode + $?))
    postinstall
    return 0
}

postinstall(){
    export WORKLOAD_TYPE=$(cat ${json_file} | jq -r .openshift_workload_node_instance_type)
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
    unset KUBECONFIG
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    export PASSWORD=$(echo ${CLUSTER_NAME} | md5sum | awk '{print $1}')
    ocm create idp -n localauth -t htpasswd --username kubeadmin --password ${PASSWORD} -c ${CLUSTER_NAME}
    ocm create user kubeadmin -c "$(_get_cluster_id ${CLUSTER_NAME})" --group=cluster-admins

    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    if [[ $WORKLOAD_TYPE != "null" ]]; then
        # create machinepool for workload nodes
        ocm create machinepool -c ${CLUSTER_NAME} --instance-type ${WORKLOAD_TYPE} --labels 'node-role.kubernetes.io/workload=' --taints 'role=workload:NoSchedule' --replicas 3 workload
    fi
    # set expiration time
    EXPIRATION_STRING=$(date -d "${EXPIRATION_TIME}" '+{"expiration_timestamp": "%FT%TZ"}')
    ocm patch /api/clusters_mgmt/v1/clusters/"$(_get_cluster_id ${CLUSTER_NAME})" <<< ${EXPIRATION_STRING}
    # Add firewall rules
    NETWORK_NAME=$(gcloud compute networks list --format="value(name)" | grep ^${CLUSTER_NAME})
    gcloud compute firewall-rules create ${NETWORK_NAME}-icmp --network ${NETWORK_NAME} --priority 101 --description 'scale-ci allow icmp' --allow icmp
    gcloud compute firewall-rules create ${NETWORK_NAME}-ssh --network ${NETWORK_NAME} --direction INGRESS --priority 102 --description 'scale-ci allow ssh' --allow tcp:22
    gcloud compute firewall-rules create ${NETWORK_NAME}-pbench --network ${NETWORK_NAME} --direction INGRESS --priority 103 --description 'scale-ci allow pbench-agents' --allow tcp:2022
    gcloud compute firewall-rules create ${NETWORK_NAME}-net --network ${NETWORK_NAME} --direction INGRESS --priority 104 --description 'scale-ci allow tcp,udp network tests' --rules tcp:20000-31000,udp:20000-31000 --action allow
    gcloud compute firewall-rules create ${NETWORK_NAME}-hostnet --network ${NETWORK_NAME} --priority 105 --description 'scale-ci allow tcp,udp hostnetwork tests' --rules tcp:32768-60999,udp:32768-60999 --action allow
    return 0
}

index_metadata(){
    if [[ ! "${INDEXDATA[*]}" =~ "cleanup" ]] ; then
        _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
        export KUBECONFIG=./kubeconfig
    fi
    METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"platform": "GCP-MS",
"network_type": "${NETWORK_TYPE}",
"aws_authentication_method": "null",
"cluster_version": "${OCM_VERSION}",
"cluster_major_version" : "${version}",
"master_count": "$(oc get node -l node-role.kubernetes.io/master= --no-headers 2>/dev/null | wc -l)",
"worker_count": "${COMPUTE_WORKERS_NUMBER}",
"infra_count": "$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
"workload_count": "$(oc get node -l node-role.kubernetes.io/workload= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
"total_node_count": "$(oc get nodes 2>/dev/null | wc -l)",
"ocp_cluster_name": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"cluster_name": "${CLUSTER_NAME}",
"timestamp": "$(date +%s%3N)"
EOF
)
    INSTALL_TIME=0
    TOTAL_TIME=0
    for i in "${INDEXDATA[@]}" ; do IFS="-" ; set -- $i
        METADATA="${METADATA}, \"$1\":\"$2\""
	      if [ $1 != "day2operations" ] && [ $1 != "cleanup" ] ; then
	          INSTALL_TIME=$((${INSTALL_TIME} + $2))
	          TOTAL_TIME=$((${TOTAL_TIME} + $2))
	      else
	          TOTAL_TIME=$((${TOTAL_TIME} + $2))
	      fi
    done
    IFS=" "
    METADATA="${METADATA}, \"install_time\":\"${INSTALL_TIME}\""
    METADATA="${METADATA}, \"total_time\":\"${TOTAL_TIME}\""
    METADATA="${METADATA} }"
    printf "Indexing installation timings to ES"
    curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/managedservices-timings/_doc -d "${METADATA}" -o /dev/null
    unset KUBECONFIG
    return 0
}

cleanup(){
    CLEANUP_START_TIMING=$(date +%s)
    ocm delete cluster "$(_get_cluster_id ${CLUSTER_NAME})"
    _wait_for_cluster_deleted "${CLUSTER_NAME}"
    exitcode=$(($exitcode + $?))
    DURATION=$(($(date +%s) - $CLEANUP_START_TIMING))
    INDEXDATA+=("cleanup-${DURATION}")
    preclean
}

preclean(){
    echo "Delete old firewall-rules.."
    for i in $(gcloud compute firewall-rules list | grep ${CLUSTER_NAME} | awk '{print$1}'); do
        gcloud compute firewall-rules delete $i --quiet || true
    done
    echo "Delete old routers.."
    for i in $(gcloud compute routers list | grep ${CLUSTER_NAME} | awk '{print$1}'); do
        gcloud compute routers delete $i --quiet --region "$(gcloud compute routers list | grep $i | awk '{print$2}')" || true
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
exitcode=$(($exitcode + $?))

if [[ "$operation" == "install" ]]; then
    printf "INFO: Checking if cluster is already installed"
    CLUSTER_STATUS=$(_get_cluster_status ${CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, precleaning & installing..."
        preclean # to cleanup any old orphaned resources from prev itr
        install
        index_metadata
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
    index_metadata
    ocm logout
    exit ${exitcode}
fi
