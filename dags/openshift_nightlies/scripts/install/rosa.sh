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
    if [[ $INSTALL_METHOD == "osd" ]]; then
        echo "$(ocm list clusters --no-headers --columns id $1)"
    else
        echo "$(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .id')"
    fi
}

_download_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$1/credentials | jq -r .kubeconfig > $2
}

_get_cluster_status(){
    if [[ $INSTALL_METHOD == "osd" ]]; then
        echo "$(ocm list clusters --no-headers --columns state $1 | xargs)"
    else
        echo "$(rosa list clusters -o json | jq -r '.[] | select(.name == '\"$1\"') | .status.state')"
    fi
}

_wait_for_nodes_ready(){
    _download_kubeconfig "$(_get_cluster_id $1)" ./kubeconfig
    export KUBECONFIG=./kubeconfig
    ALL_READY_ITERATIONS=0
    ITERATIONS=0
    if [ $HCP == "true" ]; then
        NODES_COUNT=$2
        ALL_READY_ITERATIONS=5
    else
        # Node count is number of workers + 3 masters + 3 infra
        NODES_COUNT=$(($2+6))
    fi
    # 180 seconds per node, waiting 5 times 60 seconds (5*60 = 5 minutes) with all nodes ready to finalize
    while [ ${ITERATIONS} -le $((${NODES_COUNT}+2)) ] ; do
        NODES_READY_COUNT=$(oc get nodes | grep " Ready " | wc -l)
        if [ ${NODES_READY_COUNT} -ne ${NODES_COUNT} ] ; then
            echo "WARNING: ${ITERATIONS}/${NODES_COUNT} iterations. ${NODES_READY_COUNT}/${NODES_COUNT} nodes ready. Waiting 180 seconds for next check"
            # ALL_READY_ITERATIONS=0
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
    END_CLUSTER_STATUS="Ready. No Workers"
    echo "ERROR: Not all nodes (${NODES_READY_COUNT}/${NODES_COUNT}) are ready after about $((${NODES_COUNT}*3)) minutes, dumping oc get nodes..."
    oc get nodes
    exit 1
}

_aws_cmd(){
    ITR=0
    while [ $ITR -le 20 ]; do
        if [[ "$(aws ec2 $1 2>&1)" == *"error"* ]]; then
            echo "Failed to $1, retrying after 30 seconds"
            ITR=$(($ITR+1))
            sleep 10
        else
            return 0
        fi
    done
}

_login_check(){
    echo "Trying to oc login with password"
    ITR=1
    START_TIMER=$(date +%s)
    while [ $ITR -le 100 ]; do
        if [[ "$(oc login $1 --username cluster-admin --password $2 --insecure-skip-tls-verify=true --request-timeout=30s 2>&1)" == *"failed"* ]]; then
            echo "Attempt $ITR: Failed to login $1, retrying after 5 seconds"
            ITR=$(($ITR+1))
            sleep 5
        else
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("login-${DURATION}")
            return 0
        fi
    done    
    END_CLUSTER_STATUS="Ready. Not Access"
    echo "Failed to login after 100 attempts with 5 sec interval"
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
            END_CLUSTER_STATUS="Ready"
            echo "Set end time of prom scrape"
            export END_TIME=$(date +"%s")       
            START_TIMER=$(date +%s)
            _wait_for_nodes_ready $1 ${COMPUTE_WORKERS_NUMBER}
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("day2operations-${DURATION}")
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
        END_CLUSTER_STATUS="Not Ready"
        echo "ERROR: Cluster $1 not installed after 90 iterations, dumping installation logs..."
        rosa logs install -c $1
        rosa describe cluster -c $1
    fi
    exit 1
}

_create_aws_vpc(){

    echo "Allocate Elastic IP"
    aws ec2 allocate-address  --tag-specifications ResourceType=elastic-ip,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=eip-$CLUSTER_NAME}]" --output json
    export E_IP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=eip-$CLUSTER_NAME" --output json | jq -r ".Addresses[0].AllocationId")
    
    echo "Create Internet Gateway"
    aws ec2 create-internet-gateway --tag-specifications ResourceType=internet-gateway,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=igw-$CLUSTER_NAME}]" --output json
    export IGW=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=igw-$CLUSTER_NAME" --output json | jq -r ".InternetGateways[0].InternetGatewayId")
    
    echo "Create VPC and attach internet gateway"
    aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications ResourceType=vpc,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=vpc-$CLUSTER_NAME}]" --output json
    export VPC=$(aws ec2 describe-vpcs --filters "Name=tag:HostedClusterName,Values=$CLUSTER_NAME" --output json | jq -r '.Vpcs[0].VpcId')

    aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support "{\"Value\":true}" 
    aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames "{\"Value\":true}"
    aws ec2 attach-internet-gateway --vpc-id $VPC --internet-gateway-id $IGW

    echo "Create Subnets and Route tables"
    aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.1.0/24 --tag-specifications ResourceType=subnet,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=public-subnet-$CLUSTER_NAME}]" --output json
    export PUB_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-subnet-$CLUSTER_NAME" --output json | jq -r ".Subnets[0].SubnetId")
    aws ec2 create-nat-gateway --subnet-id $PUB_SUB --allocation-id $E_IP --tag-specifications ResourceType=natgateway,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=ngw-$CLUSTER_NAME}]" --output json
    export NGW=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ngw-$CLUSTER_NAME" --output json | jq -r ".NatGateways[]" | jq -r 'select(.State == "available" or .State  == "pending")' | jq -r ".NatGatewayId")
    aws ec2 create-route-table --vpc-id $VPC --tag-specifications ResourceType=route-table,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=public-rt-table-$CLUSTER_NAME}]" --output json
    export PUB_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
    aws ec2 associate-route-table --route-table-id $PUB_RT_TB --subnet-id $PUB_SUB
    aws ec2 create-route --route-table-id $PUB_RT_TB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

    aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.2.0/24 --tag-specifications ResourceType=subnet,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=private-subnet-$CLUSTER_NAME}]" --output json
    export PRI_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-subnet-$CLUSTER_NAME" --output json | jq -r ".Subnets[0].SubnetId")
    aws ec2 create-route-table --vpc-id $VPC --tag-specifications ResourceType=route-table,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=private-rt-table-$CLUSTER_NAME}]" --output json
    export PRI_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
    aws ec2 associate-route-table --route-table-id $PRI_RT_TB --subnet-id $PRI_SUB
    aws ec2 create-route --route-table-id $PRI_RT_TB --destination-cidr-block 0.0.0.0/0 --gateway-id $NGW

    echo "Create private VPC endpoint to S3"
    aws ec2 create-vpc-endpoint --vpc-id $VPC --service-name com.amazonaws.$AWS_REGION.s3 --route-table-ids $PRI_RT_TB --tag-specifications ResourceType=vpc-endpoint,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=vpce-$CLUSTER_NAME}]"
}

_delete_aws_vpc(){
    echo "Delete Subnets, Routes, Gateways, VPC if exists"
    export VPC=$(aws ec2 describe-vpcs --filters "Name=tag:HostedClusterName,Values=$CLUSTER_NAME" --output json | jq -r '.Vpcs[0].VpcId')
    if [ $VPC != null ]; then 
        echo "Delete VPC Endpoint"
        export VPCE=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=vpce-$CLUSTER_NAME" --output json | jq -r '.VpcEndpoints[0].VpcEndpointId')
        if [ $VPCE != null ]; then _aws_cmd "delete-vpc-endpoints --vpc-endpoint-ids $VPCE"; fi

        echo "Delete Subnets and Route tables"
        export PRI_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
        export RT_TB_ASSO_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].Associations[0].RouteTableAssociationId')
        export PRI_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-subnet-$CLUSTER_NAME" --output json | jq -r ".Subnets[0].SubnetId")

        if [ $PRI_RT_TB != null ]; then _aws_cmd "delete-route --route-table-id $PRI_RT_TB --destination-cidr-block 0.0.0.0/0"; fi
        if [ $RT_TB_ASSO_ID != null ]; then _aws_cmd "disassociate-route-table --association-id $RT_TB_ASSO_ID"; fi
        if [ $PRI_RT_TB != null ]; then _aws_cmd "delete-route-table --route-table-id $PRI_RT_TB"; fi
        if [ $PRI_SUB != null ]; then _aws_cmd "delete-subnet --subnet-id $PRI_SUB"; fi

        export PUB_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
        export RT_TB_ASSO_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].Associations[0].RouteTableAssociationId')
        export NGW=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ngw-$CLUSTER_NAME" --output json | jq -r ".NatGateways[]" | jq -r 'select(.State == "available")' | jq -r ".NatGatewayId")
        export PUB_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-subnet-$CLUSTER_NAME" --output json | jq -r ".Subnets[0].SubnetId")
        export E_IP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=eip-$CLUSTER_NAME" --output json | jq -r ".Addresses[0].AllocationId")

        if [ $PUB_RT_TB != null ]; then _aws_cmd "delete-route --route-table-id $PUB_RT_TB --destination-cidr-block 0.0.0.0/0"; fi
        if [ $RT_TB_ASSO_ID != null ]; then _aws_cmd "disassociate-route-table --association-id $RT_TB_ASSO_ID"; fi
        if [ $PUB_RT_TB != null ]; then _aws_cmd "delete-route-table --route-table-id $PUB_RT_TB"; fi
        if [ $NGW != null ]; then _aws_cmd "delete-nat-gateway --nat-gateway-id $NGW"; fi
        if [ $PUB_SUB != null ]; then _aws_cmd "delete-subnet --subnet-id $PUB_SUB"; fi
        if [ $E_IP != null ]; then _aws_cmd "release-address --allocation-id $E_IP"; fi
        
        export IGW=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=igw-$CLUSTER_NAME" --output json | jq -r ".InternetGateways[0].InternetGatewayId")
        if [ $IGW != null ]; then _aws_cmd "detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC"; fi
        if [ $IGW != null ]; then _aws_cmd "delete-internet-gateway --internet-gateway-id $IGW"; fi

        echo "Delete Security Group Rules"
        for g in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --output json | jq -r ".SecurityGroups[].GroupId"); 
        do 
            for r in $(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$g" --output json | jq -r ".SecurityGroupRules[]" | jq -r "select(.IsEgress == false)" | jq -r ".SecurityGroupRuleId");
                do 
                    aws ec2 revoke-security-group-ingress --security-group-rule-ids $r  --group-id  $g
                done

            for r in $(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$g" --output json | jq -r ".SecurityGroupRules[]" | jq -r "select(.IsEgress == true)" | jq -r ".SecurityGroupRuleId");
                do 
                    aws ec2 revoke-security-group-egress --security-group-rule-ids $r  --group-id  $g
                done
        done

        for g in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --output json | jq -r ".SecurityGroups[]" | jq -r 'select(.GroupName != "default")' | jq -r ".GroupId"); 
        do 
            echo "Delete Security Groups $g"
            _aws_cmd "delete-security-group --group-id $g"
        done

        echo "Delete VPC $VPC"
        _aws_cmd "delete-vpc --vpc-id $VPC"
    fi
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
    export HCP=$(cat ${json_file} | jq -r .rosa_hcp)
    export UUID=$(uuidgen)
    if [ $HCP == "true" ]; then
        export STAGE_CONFIG=""
        export MGMT_CLUSTER_NAME=$(cat ${json_file} | jq -r .staging_mgmt_cluster_name)
        export SVC_CLUSTER_NAME=$(cat ${json_file} | jq -r .staging_svc_cluster_name)
        export CLUSTER_NAME="${CLUSTER_NAME}-${HOSTED_ID}" # perf-as3-hcp-1, perf-as3-hcp-2..
        export KUBECONFIG_NAME=$(echo $KUBECONFIG_NAME | awk -F-kubeconfig '{print$1}')-$HOSTED_ID-kubeconfig
        export KUBEADMIN_NAME=$(echo $KUBEADMIN_NAME | awk -F-kubeadmin '{print$1}')-$HOSTED_ID-kubeadmin
        UUID=$(echo $AIRFLOW_CTX_DAG_RUN_ID | base64 | cut -c 1-32 )
        export UUID=${UUID,,}
    fi
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
        if [[ ${OCM_CLI_VERSION} != "container" ]]; then
            OCM_CLI_FORK=$(cat ${json_file} | jq -r .ocm_cli_fork)
            git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
            pushd ocm-cli
            sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
            sudo mv ocm /usr/local/bin/
            popd
        fi
        echo "Clean-up existing OSD access keys.."
        AWS_KEY=$(aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId')
        LEN_AWS_KEY=`echo $AWS_KEY | wc -w`
        if [[  ${LEN_AWS_KEY} -eq 2 ]]; then
            aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id `printf ${AWS_KEY[0]}`
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
    fi
}

install(){
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    export CLUSTER_AUTOSCALE=$(cat ${json_file} | jq -r .cluster_autoscale)
    if [[ $INSTALL_METHOD == "osd" ]]; then
	if [ "${MANAGED_OCP_VERSION}" == "latest" ] ; then
            export OCM_VERSION=$(ocm list versions --channel-group ${MANAGED_CHANNEL_GROUP} | grep ^${version} | sort -rV | head -1)
	elif [ "${MANAGED_OCP_VERSION}" == "prelatest" ] ; then
            export OCM_VERSION=$(ocm list versions --channel-group ${MANAGED_CHANNEL_GROUP} | grep ^${version} | sort -rV | head -2 | tail -1)
	else
            export OCM_VERSION=$(ocm list versions --channel-group ${MANAGED_CHANNEL_GROUP} | grep ^${MANAGED_OCP_VERSION})
	fi
        [ -z ${OCM_VERSION} ] && echo "ERROR: Image not found for version (${version}) on OCM ${MANAGED_CHANNEL_GROUP} channel group" && exit 1
        if [[ $CLUSTER_AUTOSCALE == "true" ]]; then
            export MIN_COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .min_openshift_worker_count) 
            export CLUSTER_SIZE="--enable-autoscaling --min-replicas ${MIN_COMPUTE_WORKERS_NUMBER} --max-replicas ${COMPUTE_WORKERS_NUMBER}"
        else
            export CLUSTER_SIZE="--compute-nodes ${COMPUTE_WORKERS_NUMBER}"
        fi
        ocm create cluster --ccs --provider aws --region ${AWS_REGION} --aws-account-id ${AWS_ACCOUNT_ID} --aws-access-key-id ${AWS_ACCESS_KEY_ID} --aws-secret-access-key ${AWS_SECRET_ACCESS_KEY} --channel-group ${MANAGED_CHANNEL_GROUP} --version ${OCM_VERSION} --multi-az  --compute-machine-type ${COMPUTE_WORKERS_TYPE} --network-type ${NETWORK_TYPE} ${CLUSTER_NAME} ${CLUSTER_SIZE}
    else
        export INSTALLATION_PARAMS=""
        export ROSA_HCP_PARAMS=""
        if [ $AWS_AUTHENTICATION_METHOD == "sts" ] ; then
            INSTALLATION_PARAMS="${INSTALLATION_PARAMS} --sts -m auto --yes"
        fi
        if [ $HCP == "true" ]; then
            export STAGE_PROV_SHARD=$(cat ${json_file} | jq -r .staging_mgmt_provisioner_shards)
            echo "Read Management cluster details"
            export MGMT_CLUSTER_DETAILS=$(ocm get /api/clusters_mgmt/v1/clusters | jq -r ".items[]" | jq -r 'select(.name == '\"$MGMT_CLUSTER_NAME\"')')
            export NUMBER_OF_HC=$(cat ${json_file} | jq -r .number_of_hostedcluster)
            echo "Index Managment cluster info"
            index_metadata "management"  
            _create_aws_vpc
            echo "Set start time of prom scrape"
            export START_TIME=$(date +"%s")
            if [ $STAGE_PROV_SHARD != "" ]; then
                STAGE_CONFIG="--properties provision_shard_id:${STAGE_PROV_SHARD}"
            fi
            ROSA_HCP_PARAMS="--hosted-cp ${STAGE_CONFIG} --subnet-ids $PRI_SUB,$PUB_SUB --machine-cidr 10.0.0.0/16"
        else
            INSTALLATION_PARAMS="${INSTALLATION_PARAMS} --multi-az"  # Multi AZ is not supported on hosted-cp cluster
        fi
        rosa create cluster --tags=User:${GITHUB_USERNAME} --cluster-name ${CLUSTER_NAME} --version "${ROSA_VERSION}" --channel-group=${MANAGED_CHANNEL_GROUP} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --replicas ${COMPUTE_WORKERS_NUMBER} --network-type ${NETWORK_TYPE} ${INSTALLATION_PARAMS} ${ROSA_HCP_PARAMS}
    fi
    _wait_for_cluster_ready ${CLUSTER_NAME}
    postinstall
    return 0
}

postinstall(){
    # sleeping to address issue #324
    sleep 120
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
    unset KUBECONFIG
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export PASSWORD=$(echo ${CLUSTER_NAME} | md5sum | awk '{print $1}')
        ocm create idp -n localauth -t htpasswd --username kubeadmin --password ${PASSWORD} -c ${CLUSTER_NAME}
        ocm create user kubeadmin -c "$(_get_cluster_id ${CLUSTER_NAME})" --group=cluster-admins
        # set expiration time
        EXPIRATION_STRING=$(date -d "${EXPIRATION_TIME} minutes" '+{"expiration_timestamp": "%FT%TZ"}')
        ocm patch /api/clusters_mgmt/v1/clusters/"$(_get_cluster_id ${CLUSTER_NAME})" <<< ${EXPIRATION_STRING}
        echo "Cluster is ready, deleting OSD access keys now.."
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY_ID || true
    else
        URL=$(rosa describe cluster -c $CLUSTER_NAME --output json | jq -r ".api.url")
        PASSWORD=$(rosa create admin -c "$(_get_cluster_id ${CLUSTER_NAME})" -y 2>/dev/null | grep "oc login" | awk '{print $7}')
        if [ $HCP == "true" ]; then _login_check $URL $PASSWORD; fi
        # set expiration to 24h
        rosa edit cluster -c "$(_get_cluster_id ${CLUSTER_NAME})" --expiration=${EXPIRATION_TIME}m
    fi
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    if [ $HCP == "true" ]; then index_metadata "cluster-install"; fi
    return 0
}

index_metadata(){
    if [[ ! "${INDEXDATA[*]}" =~ "cleanup" ]] ; then
        _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
        export KUBECONFIG=./kubeconfig
    fi
    if [[ $INSTALL_METHOD == "osd" ]]; then
        export PLATFORM="AWS-MS"
        export CLUSTER_VERSION="${OCM_VERSION}"
    else
        export PLATFORM="ROSA"
        export CLUSTER_VERSION="${ROSA_VERSION}"
    fi
    if [ $HCP == "true" ]; then
        if [ "$1" ==  "management" ]; then
            METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"aws_authentication_method": "${AWS_AUTHENTICATION_METHOD}",
"version": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".openshift_version")",
"infra_id": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".infra_id")",
"cluster_name": "$MGMT_CLUSTER_NAME",
"cluster_id": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".id")",
"base_domain": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".dns.base_domain")",
"aws_region": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".region.id")",
"workers": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".nodes.autoscale_compute.max_replicas")",
"workers_type": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".nodes.compute_machine_type.id")",
"network_type": "$(echo $MGMT_CLUSTER_DETAILS | jq -r ".network.type")",
"install_method": "rosa",
"provision_shard": "$STAGE_PROV_SHARD",
"hostedclusters": "$NUMBER_OF_HC"
}
EOF
)
        elif [ "$1" == "cluster-install" ]; then
            METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"aws_authentication_method": "${AWS_AUTHENTICATION_METHOD}",
"mgmt_cluster_name": "$MGMT_CLUSTER_NAME",
"workers": "$COMPUTE_WORKERS_NUMBER",
"cluster_name": "${CLUSTER_NAME}",
"cluster_id": "$(_get_cluster_id ${CLUSTER_NAME})",
"network_type": "${NETWORK_TYPE}",
"version": "${CLUSTER_VERSION}",
"operation": "install",
"install_method": "rosa",
"status": "$END_CLUSTER_STATUS",
"timestamp": "$(date +%s%3N)"
EOF
)
            INSTALL_TIME=0
            TOTAL_TIME=0
            for i in "${INDEXDATA[@]}" ; do IFS="-" ; set -- $i
                METADATA="${METADATA}, \"$1\":\"$2\""
            if [ $1 != "day2operations" ] && [ $1 != "login" ] ; then
                INSTALL_TIME=$((${INSTALL_TIME} + $2))
            elif [ $1 == "day2operations" ]; then
                WORKER_READY_TIME=$2
            elif [ $1 == "login" ]; then
                LOGIN_TIME=$2
            else
                TOTAL_TIME=$2
            fi
            done
            IFS=" "
            METADATA="${METADATA}, \"duration\":\"${INSTALL_TIME}\""
            METADATA="${METADATA}, \"workers_ready\":\"$(($INSTALL_TIME + $WORKER_READY_TIME))\""
            METADATA="${METADATA}, \"cluster-admin-login\":\"${LOGIN_TIME}\""
            METADATA="${METADATA} }"
        else
           METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
"mgmt_cluster_name": "$MGMT_CLUSTER_NAME",
"workers": "$COMPUTE_WORKERS_NUMBER",
"cluster_name": "${CLUSTER_NAME}",
"cluster_id": "$ROSA_CLUSTER_ID",
"network_type": "${NETWORK_TYPE}",
"version": "${CLUSTER_VERSION}",
"operation": "destroy",
"install_method": "rosa",
"duration": "$DURATION",
"timestamp": "$(date +%s%3N)"
}
EOF
)
        fi
        printf "Indexing installation timings to ES"
        curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/hypershift-wrapper-timers/_doc -d "${METADATA}" -o /dev/null
    else
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
    fi
    unset KUBECONFIG
    return 0
}

index_mgmt_cluster_stat(){
    echo "Indexing Management cluster stat..."
    cd /home/airflow/workspace    
    echo "Installing kube-burner"
    export KUBE_BURNER_RELEASE=${KUBE_BURNER_RELEASE:-1.3}
    curl -L https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_RELEASE}/kube-burner-${KUBE_BURNER_RELEASE}-Linux-x86_64.tar.gz -o kube-burner.tar.gz
    sudo tar -xvzf kube-burner.tar.gz -C /usr/local/bin/
    echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
    git clone -q -b ${E2E_BENCHMARKING_BRANCH}  ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
    export MGMT_CLUSTER_NAME="$MGMT_CLUSTER_NAME.*"
    export SVC_CLUSTER_NAME="$SVC_CLUSTER_NAME.*"
    export HOSTED_CLUSTER_NS=".*$CLUSTER_NAME"
    export HOSTED_CLUSTER_NAME="$1-$CLUSTER_NAME"
    export Q_TIME=$(date +"%s")
    envsubst < /home/airflow/workspace/e2e-benchmarking/workloads/kube-burner/metrics-profiles/hypershift-metrics.yaml > hypershift-metrics.yaml
    envsubst < /home/airflow/workspace/e2e-benchmarking/workloads/kube-burner/workloads/managed-services/baseconfig.yml > baseconfig.yml
    METADATA=$(cat << EOF
{
"uuid":"${UUID}",
"platform":"${PLATFORM}",
"sdn_type":"${NETWORK_TYPE}",
"timestamp": "$(date +%s%3N)",
"cluster_name": "${HOSTED_CLUSTER_NAME}",
"mgmt_cluster_name": "${MGMT_CLUSTER_NAME}",
"svc_cluster_name": "${SVC_CLUSTER_NAME}"
}
EOF
)
    printf "Indexing metadata to ES"
    curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${ES_INDEX}/_doc -d "${METADATA}" -o /dev/null

    echo "Running kube-burner index.." 
    kube-burner index --uuid=${UUID} --prometheus-url=${PROM_URL} --start=$START_TIME --end=$END_TIME --step 2m --metrics-profile hypershift-metrics.yaml --config baseconfig.yml
    echo "Finished indexing results"
}

cleanup(){
    if [[ $INSTALL_METHOD == "osd" ]]; then
        ocm delete cluster "$(_get_cluster_id ${CLUSTER_NAME})"
        echo "Cluster is getting Uninstalled, deleting OSD access keys now.."
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY_ID || true
    else
        export ROSA_CLUSTER_ID=$(_get_cluster_id ${CLUSTER_NAME})
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
        if [ $HCP == "true" ]; then
            _delete_aws_vpc
        fi
    fi
    return 0
}

export INSTALL_METHOD=$(cat ${json_file} | jq -r .cluster_install_method)
export HC_INTERVAL=$(cat ${json_file} | jq -r .hcp_install_interval)
SKEW_FACTOR=$(echo $HOSTED_ID|awk -F- '{print$2}')
sleep $(($HC_INTERVAL*$SKEW_FACTOR)) # 60*1, 60*2..
setup

if [[ "$operation" == "install" ]]; then
    printf "INFO: Checking if cluster is already installed"
    CLUSTER_STATUS=$(_get_cluster_status ${CLUSTER_NAME})
    if [ -z "${CLUSTER_STATUS}" ] ; then
        printf "INFO: Cluster not found, installing..."
        if [ $HCP == "true" ]; then 
            echo "pre-clean AWS resources" 
            _delete_aws_vpc
            install
            index_mgmt_cluster_stat "install-metrics"
        else
            install
            index_metadata
        fi
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
    if [ $HCP == "true" ]; then index_mgmt_cluster_stat "destroy-metrics"; fi
    rosa logout
    ocm logout    
fi
