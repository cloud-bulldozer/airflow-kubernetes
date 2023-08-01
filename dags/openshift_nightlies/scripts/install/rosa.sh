#!/bin/bash
# shellcheck disable=SC2155
set -ex

export INDEXDATA=()

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
    echo "$(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .id')"
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    echo "$(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .status.state')"
}

_wait_for_nodes_ready(){
    _download_kubeconfig "$(_get_cluster_id $1)" ./kubeconfig
    export KUBECONFIG=./kubeconfig
    ALL_READY_ITERATIONS=0
    ITERATIONS=0
    # Node count is number of workers + 3 infra
    NODES_COUNT=$(($2+3))
    # 30 seconds per node, waiting for all nodes ready to finalize
    while [ ${ITERATIONS} -le $((${NODES_COUNT}*5)) ] ; do
        NODES_READY_COUNT=$(oc get nodes -l $3 | grep " Ready " | wc -l)
        if [ ${NODES_READY_COUNT} -ne ${NODES_COUNT} ] ; then
            echo "WARNING: ${ITERATIONS}/${NODES_COUNT} iterations. ${NODES_READY_COUNT}/${NODES_COUNT} $3 nodes ready. Waiting 30 seconds for next check"
            # ALL_READY_ITERATIONS=0
            ITERATIONS=$((${ITERATIONS}+1))
            sleep 30
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
    END_CLUSTER_STATUS="Ready. No Workers"
    echo "ERROR: Not all $3 nodes (${NODES_READY_COUNT}/${NODES_COUNT}) are ready after about $((${NODES_COUNT}*3)) minutes, dumping oc get nodes..."
    oc get nodes
    exit 1
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
        CLUSTER_STATUS=$(_get_cluster_status $1)
        CURRENT_TIMER=$(date +%s)
        if [ ${CLUSTER_STATUS} != ${PREVIOUS_STATUS} ] && [ ${PREVIOUS_STATUS} != "" ]; then
            # When detected a status change, index timer and update start time for next status change
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("${PREVIOUS_STATUS}"-"${DURATION}")
            START_TIMER=${CURRENT_TIMER}
            echo "INFO: Cluster status changed to ${CLUSTER_STATUS}"
            if [ ${CLUSTER_STATUS} == "error" ] ; then
                rosa logs install -c $1
                rosa describe cluster -c $1
                return 1
            fi
        fi
        if [ ${CLUSTER_STATUS} == "ready" ] ; then
            END_CLUSTER_STATUS="Ready"
            echo "Set end time of prom scrape"
            export END_TIME=$(date +"%s")       
            START_TIMER=$(date +%s)
            _wait_for_nodes_ready $1 ${COMPUTE_WORKERS_NUMBER} "node-role.kubernetes.io/worker"
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("day2operations-${DURATION}")
            echo "INFO: Cluster and nodes on ready status at ${CURRENT_TIMER}, dumping installation logs..."
            rosa logs install -c $1
            rosa describe cluster -c $1
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
    END_CLUSTER_STATUS="Not Ready"
    echo "ERROR: Cluster $1 not installed after 90 iterations, dumping installation logs..."
    rosa logs install -c $1
    rosa describe cluster -c $1

    exit 1
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export AWS_REGION=$(cat ${json_file} | jq -r .aws_region)
    export AWS_ACCOUNT_ID=$(cat ${json_file} | jq -r .aws_account_id)
    export AWS_ACCESS_KEY_ID=$(cat ${json_file} | jq -r .aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat ${json_file} | jq -r .aws_secret_access_key)
    export AWS_AUTHENTICATION_METHOD=$(cat ${json_file} | jq -r .aws_authentication_method)
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export MANAGED_OCP_VERSION=$(cat ${json_file} | jq -r .managed_ocp_version)
    export MANAGED_CHANNEL_GROUP=$(cat ${json_file} | jq -r .managed_channel_group)
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export ES_SERVER=$(cat ${json_file} | jq -r .es_server)
    export UUID=$(uuidgen)
    export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
    if [[ ${OCM_CLI_VERSION} != "container" ]]; then
        OCM_CLI_FORK=$(cat ${json_file} | jq -r .ocm_cli_fork)
        git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
        pushd ocm-cli
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd
    fi    
    export ROSA_CLI_VERSION=$(cat ${json_file} | jq -r .rosa_cli_version)
    if [[ ${ROSA_CLI_VERSION} != "container" ]]; then
        ROSA_CLI_FORK=$(cat ${json_file} | jq -r .rosa_cli_fork)
        git clone -q --depth=1 --single-branch --branch ${ROSA_CLI_VERSION} ${ROSA_CLI_FORK}
        pushd rosa
        make
        sudo mv rosa /usr/local/bin/
        popd
    fi
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    ocm whoami
    rosa login --env=${ROSA_ENVIRONMENT}
    rosa whoami
    rosa verify quota
    rosa verify permissions
    if [ "${MANAGED_OCP_VERSION}" == "latest" ] ; then
        export ROSA_VERSION=$(rosa list versions -o json --channel-group=${MANAGED_CHANNEL_GROUP} | jq -r '.[] | select(.raw_id|startswith('\"${version}\"')) | .raw_id' | sort -rV | head -1)
    elif [ "${MANAGED_OCP_VERSION}" == "prelatest" ] ; then
        export ROSA_VERSION=$(rosa list versions -o json --channel-group=${MANAGED_CHANNEL_GROUP} | jq -r '.[] | select(.raw_id|startswith('\"${version}\"')) | .raw_id' | sort -rV | head -2 | tail -1)
    else
        export ROSA_VERSION=$(rosa list versions -o json --channel-group=${MANAGED_CHANNEL_GROUP} | jq -r '.[] | select(.raw_id|startswith('\"${version}\"')) | .raw_id' | grep ^${MANAGED_OCP_VERSION}$)
    fi
    [ -z "${ROSA_VERSION}" ] && echo "ERROR: Image not found for version (${version}) on ROSA ${MANAGED_CHANNEL_GROUP} channel group" && exit 1
    return 0
}

install(){
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    export CLUSTER_AUTOSCALE=$(cat ${json_file} | jq -r .cluster_autoscale)
    export OIDC_CONFIG=$(cat ${json_file} | jq -r .oidc_config)
    export INSTALLATION_PARAMS=""
    if [ $AWS_AUTHENTICATION_METHOD == "sts" ] ; then
        INSTALLATION_PARAMS="${INSTALLATION_PARAMS} --sts -m auto --yes"
    fi
    INSTALLATION_PARAMS="${INSTALLATION_PARAMS} --multi-az"  # Multi AZ is default on hosted-cp cluster
    rosa create cluster --tags=User:${GITHUB_USERNAME} --cluster-name ${CLUSTER_NAME} --version "${ROSA_VERSION}" --channel-group=${MANAGED_CHANNEL_GROUP} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --replicas ${COMPUTE_WORKERS_NUMBER} --network-type ${NETWORK_TYPE} ${INSTALLATION_PARAMS} 
    postinstall
    return 0
}

postinstall(){
    _wait_for_cluster_ready ${CLUSTER_NAME}
    # sleeping to address issue #324
    sleep 120
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
    unset KUBECONFIG
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    URL=$(rosa describe cluster -c $CLUSTER_NAME --output json | jq -r ".api.url")
    START_TIMER=$(date +%s)      
    PASSWORD=$(rosa create admin -c "$(_get_cluster_id ${CLUSTER_NAME})" -y 2>/dev/null | grep "oc login" | awk '{print $7}')
    CURRENT_TIMER=$(date +%s)
    DURATION=$(($CURRENT_TIMER - $START_TIMER))
    INDEXDATA+=("cluster_admin_create-${DURATION}")  
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    # set expiration to 24h
    rosa edit cluster -c "$(_get_cluster_id ${CLUSTER_NAME})" --expiration=${EXPIRATION_TIME}m
    return 0
}

index_metadata(){
    if [[ ! "${INDEXDATA[*]}" =~ "cleanup" ]] ; then
        _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
        export KUBECONFIG=./kubeconfig
    fi
    export PLATFORM="ROSA"
    export CLUSTER_VERSION="${ROSA_VERSION}"

    METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"platform": "${PLATFORM}",
"network_type": "${NETWORK_TYPE}",
"aws_authentication_method": "${AWS_AUTHENTICATION_METHOD}",
"cluster_version": "${CLUSTER_VERSION}",
"cluster_major_version" : "${version}",
"master_count": "$(oc get node -l node-role.kubernetes.io/master= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
"worker_count": "${COMPUTE_WORKERS_NUMBER}",
"infra_count": "$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
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
    export ROSA_CLUSTER_ID=$(_get_cluster_id ${CLUSTER_NAME})
    export HC_INFRASTRUCTURE_NAME=${ROSA_CLUSTER_ID}
    CLEANUP_START_TIMING=$(date +%s)
    export START_TIME=$CLEANUP_START_TIMING
    rosa delete cluster -c ${ROSA_CLUSTER_ID} -y
    rosa logs uninstall -c ${ROSA_CLUSTER_ID} --watch
    if [ $AWS_AUTHENTICATION_METHOD == "sts" ] ; then
        rosa delete operator-roles -c ${ROSA_CLUSTER_ID} -m auto --yes || true
        rosa delete oidc-provider -c ${ROSA_CLUSTER_ID} -m auto --yes || true
    fi
    DURATION=$(($(date +%s) - $CLEANUP_START_TIMING))
    INDEXDATA+=("cleanup-${DURATION}")
    export END_TIME=$(date +"%s")
    return 0
}

setup

if [[ "$operation" == "install" ]]; then
    printf "INFO: Checking if cluster is already installed"
    CLUSTER_STATUS=$(_get_cluster_status ${CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, installing..."
        install
        index_metadata
    elif [ "${CLUSTER_STATUS}" == "ready" ] ; then
        printf "INFO: Cluster ${CLUSTER_NAME} already installed and ready, reusing..."
        postinstall
    elif [ "${CLUSTER_STATUS}" == "error" ] ; then
        printf "INFO: Cluster ${CLUSTER_NAME} errored, cleaning them now..."
        cleanup
        printf "INFO: Fail this install to re-try a fresh install"
        exit 1
    else
        printf "INFO: Cluster ${CLUSTER_NAME} already installed but not ready, exiting..."
        exit 1
    fi

elif [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
    cleanup
    index_metadata
    rosa logout
    ocm logout    
fi
