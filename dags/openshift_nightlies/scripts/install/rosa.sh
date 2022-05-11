#!/bin/bash

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
    if [[ $INSTALL_METHOD == "osd" ]]; then
        echo $(ocm list clusters --no-headers --columns id $1)
    else
        echo $(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .id')
    fi
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    if [[ $INSTALL_METHOD == "osd" ]]; then
        echo $(ocm list clusters --no-headers --columns state $1)
    else    
        echo $(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .status.state')
    fi
}

_wait_for_nodes_ready(){
    _download_kubeconfig $(_get_cluster_id $1) ./kubeconfig
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
    exit 1
}

_wait_for_nodes_ready(){
    _download_kubeconfig $(_get_cluster_id $1) ./kubeconfig
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
                if [[ $INSTALL_METHOD == "osd" ]]; then
                    echo "ERROR: Cluster $1 not installed after 1.5 hours.."
                else
                    rosa logs install -c $1
                    rosa describe cluster -c $1
                fi
                return 1
            fi
        fi
        if [ ${CLUSTER_STATUS} == "ready" ] ; then
            START_TIMER=$(date +%s)
            _wait_for_nodes_ready $1 ${COMPUTE_WORKERS_NUMBER}
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("day2operations"-"${DURATION}")
            if [[ $INSTALL_METHOD == "osd" ]]; then
                echo "INFO: Cluster and nodes on ready status.."
            else
                echo "INFO: Cluster and nodes on ready status at ${CURRENT_TIMER}, dumping installation logs..."
                rosa logs install -c $1
                rosa describe cluster -c $1
            fi
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
    if [[ $INSTALL_METHOD == "osd" ]]; then
        echo "ERROR: Cluster $1 not installed after 3 hours.."
    else    
        echo "ERROR: Cluster $1 not installed after 90 iterations, dumping installation logs..."
        rosa logs install -c $1
        rosa describe cluster -c $1
    fi
    exit 1
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export AWS_REGION=us-west-2
    export AWS_ACCOUNT_ID=$(cat ${json_file} | jq -r .aws_account_id)
    export AWS_ACCESS_KEY_ID=$(cat ${json_file} | jq -r .aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat ${json_file} | jq -r .aws_secret_access_key)
    export AWS_AUTHENTICATION_METHOD=$(cat ${json_file} | jq -r .aws_authentication_method)
    export ROSA_ENVIRONMENT=$(cat ${json_file} | jq -r .rosa_environment)
    export ROSA_TOKEN=$(cat ${json_file} | jq -r .rosa_token_${ROSA_ENVIRONMENT})
    export CLUSTER_NAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .openshift_network_type)
    export ES_SERVER=$(cat ${json_file} | jq -r .es_server)
    export UUID=$(uuidgen)    
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
        if [[ ${OCM_CLI_VERSION} == "master" ]]; then
            git clone https://github.com/openshift-online/ocm-cli
            pushd ocm-cli
            sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
            sudo mv ocm /usr/local/bin/
            popd
        fi
        echo "Create new OSD access key.."
        export ADMIN_KEY=$(aws iam create-access-key --user-name OsdCcsAdmin)
        export AWS_ACCESS_KEY_ID=$(echo $ADMIN_KEY | jq -r '.AccessKey.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_KEY | jq -r '.AccessKey.SecretAccessKey')
        ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
        ocm whoami
        sleep 60 # it takes a few sec for new access key
        echo "Check AWS Username..."
        aws iam get-user | jq -r .User.UserName        
    else
        export ROSA_CLI_VERSION=$(cat ${json_file} | jq -r .rosa_cli_version)
        if [[ ${ROSA_CLI_VERSION} == "master" ]]; then
            git clone --depth=1 --single-branch --branch master https://github.com/openshift/rosa
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
        export ROSA_VERSION=$(rosa list versions -o json --channel-group=nightly | jq -r '.[] | select(.raw_id|startswith('\"${version}\"')) | .raw_id' | sort -rV | head -1)
        [ -z "${ROSA_VERSION}" ] && echo "ERROR: Image not found for version (${version}) on ROSA Nightly channel group" && exit 1
        return 0        
    fi
}

install(){
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export OCM_VERSION=$(ocm list versions --channel-group nightly | grep ^${version} | sort -rV | head -1)
        [ -z ${OCM_VERSION} ] && echo "ERROR: Image not found for version (${version}) on OCM Nightly channel group" && exit 1
        ocm create cluster --ccs --provider aws --region ${AWS_REGION} --aws-account-id ${AWS_ACCOUNT_ID} --aws-access-key-id ${AWS_ACCESS_KEY_ID} --aws-secret-access-key ${AWS_SECRET_ACCESS_KEY} --channel-group nightly --version ${OCM_VERSION} --multi-az --compute-nodes ${COMPUTE_WORKERS_NUMBER} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --network-type ${NETWORK_TYPE} ${CLUSTER_NAME}
    else
        export INSTALLATION_PARAMS=""
        if [ $AWS_AUTHENTICATION_METHOD == "sts" ] ; then
            INSTALLATION_PARAMS="${INSTALLATION_PARAMS} --sts -m auto --yes"
        fi
        rosa create cluster --cluster-name ${CLUSTER_NAME} --version "${ROSA_VERSION}-nightly" --channel-group=nightly --multi-az --compute-machine-type ${COMPUTE_WORKERS_TYPE} --compute-nodes ${COMPUTE_WORKERS_NUMBER} --network-type ${NETWORK_TYPE} ${INSTALLATION_PARAMS}
    fi
    _wait_for_cluster_ready ${CLUSTER_NAME}
    postinstall
    return 0
}

postinstall(){
    export WORKLOAD_TYPE=$(cat ${json_file} | jq -r .openshift_workload_node_instance_type)
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig $(_get_cluster_id ${CLUSTER_NAME}) ./kubeconfig
    unset KUBECONFIG
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export PASSWORD=$(echo ${CLUSTER_NAME} | md5sum | awk '{print $1}')
        ocm create idp -n localauth -t htpasswd --username kubeadmin --password ${PASSWORD} -c ${CLUSTER_NAME}
        ocm create user kubeadmin -c $(_get_cluster_id ${CLUSTER_NAME}) --group=cluster-admins
        if [[ $WORKLOAD_TYPE != "null" ]]; then
            # create machinepool for workload nodes
            ocm create machinepool -c ${CLUSTER_NAME} --instance-type ${WORKLOAD_TYPE} --labels 'node-role.kubernetes.io/workload=' --taints 'role=workload:NoSchedule' --replicas 3 workload
        fi
        # set expiration time
        EXPIRATION_STRING=$(date -d "${EXPIRATION_TIME} minutes" '+{"expiration_timestamp": "%FT%TZ"}')
        ocm patch /api/clusters_mgmt/v1/clusters/$(_get_cluster_id ${CLUSTER_NAME}) <<< ${EXPIRATION_STRING}
        echo "Cluster is ready, deleting OSD access keys now.."
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY_ID || true
    else
        PASSWORD=$(rosa create admin -c $(_get_cluster_id ${CLUSTER_NAME}) -y 2>/dev/null | grep "oc login" | awk '{print $7}')
        if [[ $WORKLOAD_TYPE != "null" ]]; then
            # create machinepool for workload nodes
            rosa create machinepool -c ${CLUSTER_NAME} --instance-type ${WORKLOAD_TYPE} --name workload --labels node-role.kubernetes.io/workload= --taints role=workload:NoSchedule --replicas 3
        fi
        # set expiration to 24h
        rosa edit cluster -c $(_get_cluster_id ${CLUSTER_NAME}) --expiration=${EXPIRATION_TIME}m
    fi
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    return 0
}

index_metadata(){
    if [[ ! "${INDEXDATA[*]}" =~ "cleanup" ]] ; then
        _download_kubeconfig $(_get_cluster_id ${CLUSTER_NAME}) ./kubeconfig
        export KUBECONFIG=./kubeconfig
    fi
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export PLATFORM="AWS-MS"
        export CLUSTER_VERSION="${OCM_VERSION}"
    else
        export PLATFORM="ROSA"
        export CLUSTER_VERSION="${ROSA_VERSION}"
    fi
    METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"platform": "${PLATFORM}",
"network_type": "${NETWORK_TYPE}",
"aws_authentication_method": "${AWS_AUTHENTICATION_METHOD}",
"cluster_version": "${CLUSTER_VERSION}",
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
    for i in ${INDEXDATA[@]} ; do IFS="-" ; set -- $i
        METADATA="${METADATA}, \"$1\":\"$2\""
	if [ $1 != "day2operations" ] ; then
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
    printf "Indexing installation timings to ${ES_SERVER}/managedservices-install-timings"
    curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/managedservices-install-timings/_doc -d "${METADATA}" -o /dev/null
    unset KUBECONFIG
    return 0
}

cleanup(){
    if [[ $INSTALL_METHOD == "osd" ]]; then
        ocm delete cluster $(_get_cluster_id ${CLUSTER_NAME})
        echo "Cluster is getting Uninstalled, deleting OSD access keys now.."
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY_ID || true        
        ocm logout    
    else
        ROSA_CLUSTER_ID=$(_get_cluster_id ${CLUSTER_NAME})
        CLEANUP_START_TIMING=$(date +%s)
        rosa delete cluster -c ${ROSA_CLUSTER_ID} -y
        rosa logs uninstall -c ${ROSA_CLUSTER_ID} --watch
        if [ $AWS_AUTHENTICATION_METHOD == "sts" ] ; then
            rosa delete operator-roles -c ${ROSA_CLUSTER_ID} -m auto --yes || true
            rosa delete oidc-provider -c ${ROSA_CLUSTER_ID} -m auto --yes || true
        fi
        DURATION=$(($(date +%s) - $CLEANUP_START_TIMING))
        INDEXDATA+=("cleanup"-"${DURATION}")
    fi
    return 0
}

cat ${json_file}
export INSTALL_METHOD=$(cat ${json_file} | jq -r .cluster_install_method)
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
    else
        printf "INFO: Cluster ${CLUSTER_NAME} already installed but not ready, exiting..."
	    exit 1
    fi

elif [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
    cleanup
    index_metadata
    rosa logout
fi
