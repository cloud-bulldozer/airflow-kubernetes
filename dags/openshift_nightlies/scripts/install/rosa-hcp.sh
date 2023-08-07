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
    NODES_COUNT=$2
    # 30 seconds per node, waiting for all nodes ready to finalize
    while [ ${ITERATIONS} -le $((NODES_COUNT*10)) ] ; do
        NODES_READY_COUNT=$(oc get nodes -l $3 | grep " Ready " | wc -l)
        if [ ${NODES_READY_COUNT} -ne ${NODES_COUNT} ] ; then
            echo "WARNING: ${ITERATIONS}/${NODES_COUNT} iterations. ${NODES_READY_COUNT}/${NODES_COUNT} $3 nodes ready. Waiting 30 seconds for next check"
            # ALL_READY_ITERATIONS=0
            ITERATIONS=$((${ITERATIONS}+1))
            sleep 30
        else
            if [ ${ALL_READY_ITERATIONS} -eq 2 ] ; then
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

_aws_cmd(){
    ITR=0
    while [ $ITR -le 30 ]; do
        if [[ "$(aws ec2 $1 2>&1)" == *"error"* ]]; then
            echo "Failed to $1, retrying after 30 seconds"
            ITR=$(($ITR+1))
            sleep 10
        else
            return 0
        fi
    done
    echo "Failed to $1 after 10 minutes of multiple retries"
    exit 1
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
            RECHECK=1
        else
            if [[ $RECHECK -eq 10 ]]; then
                CURRENT_TIMER=$(date +%s)
                # Time since rosa cluster is ready until all nodes are ready
                DURATION=$(($CURRENT_TIMER - $START_TIMER))
                INDEXDATA+=("cluster_admin_login-${DURATION}")
                _adm_logic_check $1 $2
                return 0
            else
                echo "Rechecking login for $((10-$RECHECK)) more times"
                RECHECK=$(($RECHECK+1))
                sleep 1
            fi
        fi
    done
    END_CLUSTER_STATUS="Ready. Not Access"
    echo "Failed to login after 100 attempts with 5 sec interval"
}

_adm_logic_check(){
    ITR=1
    START_TIMER=$(date +%s)
    while [ $ITR -le 100 ]; do
        oc login $1 --username cluster-admin --password $2 --insecure-skip-tls-verify=true --request-timeout=30s
        CHECK=$(oc adm top images 2>&1 > /dev/null)
        if [[ $? != 0 ]]; then
            echo "Attempt $ITR: Failed to login $1, retrying after 5 seconds"
            ITR=$(($ITR+1))
            sleep 5
        else
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("cluster_oc_adm-${DURATION}")
            return 0
        fi
    done
    END_CLUSTER_STATUS="Ready. Not Access"
    echo "Failed to execute oc adm commands after 100 attempts with 5 sec interval" 
}

_balance_infra(){
    if [[ $1 == "prometheus-k8s" ]] ; then
        echo "Initiate migration of prometheus componenets to infra nodepools"
        oc get pods -n openshift-monitoring -o wide | grep prometheus-k8s
        oc get sts prometheus-k8s -n openshift-monitoring
        echo "Restart stateful set pods"
        oc rollout restart -n openshift-monitoring statefulset/prometheus-k8s 
        echo "Wait till they are completely restarted"
        oc rollout status -n openshift-monitoring statefulset/prometheus-k8s
        echo "Check pods status again and the hosting nodes"
        oc get pods -n openshift-monitoring -o wide | grep prometheus-k8s
    else
        echo "Initiate migration of ingress router-default pods to infra nodepools"
        echo "Add toleration to use infra nodes"
        oc patch ingresscontroller -n openshift-ingress-operator default --type merge --patch  '{"spec":{"nodePlacement":{"nodeSelector":{"matchLabels":{"node-role.kubernetes.io/infra":""}},"tolerations":[{"effect":"NoSchedule","key":"node-role.kubernetes.io/infra","operator":"Exists"}]}}}'
        echo "Wait till it gets rolled out"
        sleep 60
        oc get pods -n openshift-ingress -o wide
    fi
}

_check_infra(){
    TRY=0
    while [ $TRY -le 3 ]; do # Attempts three times to migrate pods
        FLAG_ERROR=""
        _balance_infra $1
        for node in $(oc get pods -n $2 -o wide | grep -i $1 | grep -i running | awk '{print$7}');
        do
            if [[ $(oc get nodes | grep infra | awk '{print$1}' | grep $node) != "" ]]; then
                    echo "$node is an infra node"
            else
                    echo "$1 pod on $node is not an infra node, retrying"
                    FLAG_ERROR=true
            fi
        done
        if [[ $FLAG_ERROR == "" ]]; then return 0; else TRY=$((TRY+1)); fi
    done
    echo "Failed to move $1 pods in $2 namespace"
    exit 1
}

_wait_for_extra_nodes_ready(){
    export NODE_LABLES=$(cat ${json_file} | jq -r .extra_machinepool[].labels)
    for label in $NODE_LABLES;
    do
        REPLICA=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.labels == '\"$label\"')'.replica)
        NODES_COUNT=$((REPLICA*3))
        if [[ $label == *"infra"* ]] ; then NODES_COUNT=$((REPLICA*2)); fi
        _wait_for_nodes_ready $CLUSTER_NAME $NODES_COUNT $label
        if [[ $label == *"infra"* ]] ; then
            _check_infra prometheus-k8s openshift-monitoring
            _check_infra router openshift-ingress
        fi       
    done
    return 0
}

_add_machinepool(){
    export MACHINEPOOLS=$(cat ${json_file} | jq -r .extra_machinepool[].name)
    for mcp in $MACHINEPOOLS; 
    do
        echo "Add an extra machinepool - $mcp to cluster"
        ZONES="a b c"
        MC_NAME=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.name == '\"$mcp\"')'.name)
        REPLICA=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.name == '\"$mcp\"')'.replica)
        INS_TYPE=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.name == '\"$mcp\"')'.instance_type)
        LABELS=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.name == '\"$mcp\"')'.labels)
        TAINTS=$(cat ${json_file} | jq -r .extra_machinepool[] | jq -r 'select(.name == '\"$mcp\"')'.taints)
        if [[ $MC_NAME == *"infra"* ]]; then ZONES="a b"; fi
        for ZONE in $ZONES;
        do
            if [[ $(rosa list machinepool --cluster "$(_get_cluster_id ${CLUSTER_NAME})" | grep $MC_NAME-$ZONE) == "" ]]; then
                rosa create machinepool --cluster "$(_get_cluster_id ${CLUSTER_NAME})" --name $MC_NAME-$ZONE --instance-type ${INS_TYPE} --replicas $REPLICA --availability-zone $AWS_REGION$ZONE --labels $LABELS --taints $TAINTS
            fi
        done
    done
    _wait_for_extra_nodes_ready
    return 0
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
            _wait_for_nodes_ready $1 ${COMPUTE_WORKERS_NUMBER} "node-role.kubernetes.io/worker"
            CURRENT_TIMER=$(date +%s)
            # Time since rosa cluster is ready until all nodes are ready
            DURATION=$(($CURRENT_TIMER - $START_TIMER))
            INDEXDATA+=("day2operations-${DURATION}")
            _add_machinepool $URL $PASSWORD
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

    echo "Create Internet Gateway"
    aws ec2 create-internet-gateway --tag-specifications ResourceType=internet-gateway,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=igw-$CLUSTER_NAME}]" --output json
    export IGW=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=igw-$CLUSTER_NAME" --output json | jq -r ".InternetGateways[0].InternetGatewayId")
    
    echo "Create VPC and attach internet gateway"
    aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications ResourceType=vpc,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=vpc-$CLUSTER_NAME}]" --output json
    export VPC=$(aws ec2 describe-vpcs --filters "Name=tag:HostedClusterName,Values=$CLUSTER_NAME" --output json | jq -r '.Vpcs[0].VpcId')

    aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support "{\"Value\":true}" 
    aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames "{\"Value\":true}"
    aws ec2 attach-internet-gateway --vpc-id $VPC --internet-gateway-id $IGW

    aws ec2 create-route-table --vpc-id $VPC --tag-specifications ResourceType=route-table,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=public-rt-table-$CLUSTER_NAME}]" --output json
    export PUB_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
    aws ec2 create-route --route-table-id $PUB_RT_TB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

    ITR=0
    export ALL_PRI_RT_TB=""
    for ZONE in a b c; 
    do
        ITR=$((ITR+1))
        echo "Allocate Elastic IP"
        aws ec2 allocate-address  --tag-specifications ResourceType=elastic-ip,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=eip-$CLUSTER_NAME-$AWS_REGION$ZONE}]" --output json
        export E_IP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=eip-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Addresses[0].AllocationId")

        echo "Create Subnets and Route tables"
        aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.$ITR.0/24 --availability-zone $AWS_REGION$ZONE --tag-specifications ResourceType=subnet,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=public-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE}]" --output json
        export PUB_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Subnets[0].SubnetId")
        aws ec2 create-nat-gateway --subnet-id $PUB_SUB --allocation-id $E_IP --tag-specifications ResourceType=natgateway,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=ngw-$CLUSTER_NAME-$AWS_REGION$ZONE}]" --output json
        export NGW=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ngw-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".NatGateways[]" | jq -r 'select(.State == "available" or .State  == "pending")' | jq -r ".NatGatewayId")
        echo "Wait until NatGateway $NGW is available"
        aws ec2 wait nat-gateway-available --nat-gateway-ids $NGW
        aws ec2 associate-route-table --route-table-id $PUB_RT_TB --subnet-id $PUB_SUB

        aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.$((ITR+10)).0/24 --availability-zone $AWS_REGION$ZONE --tag-specifications ResourceType=subnet,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=private-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE}]" --output json
        export PRI_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Subnets[0].SubnetId")
        aws ec2 create-route-table --vpc-id $VPC --tag-specifications ResourceType=route-table,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=private-rt-table-$CLUSTER_NAME-$AWS_REGION$ZONE}]" --output json
        export PRI_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r '.RouteTables[0].RouteTableId')
        export ALL_PRI_RT_TB="${ALL_PRI_RT_TB} ${PRI_RT_TB}"
        aws ec2 associate-route-table --route-table-id $PRI_RT_TB --subnet-id $PRI_SUB
        aws ec2 create-route --route-table-id $PRI_RT_TB --destination-cidr-block 0.0.0.0/0 --gateway-id $NGW
    done

    echo "Create private VPC endpoint to S3"
    aws ec2 create-vpc-endpoint --vpc-id $VPC --service-name com.amazonaws.$AWS_REGION.s3 --route-table-ids $ALL_PRI_RT_TB --tag-specifications ResourceType=vpc-endpoint,Tags="[{Key=HostedClusterName,Value=$CLUSTER_NAME},{Key=Name,Value=vpce-$CLUSTER_NAME}]"
}

_delete_aws_vpc(){
    echo "Delete Subnets, Routes, Gateways, VPC if exists"
    export VPC=$(aws ec2 describe-vpcs --filters "Name=tag:HostedClusterName,Values=$CLUSTER_NAME" --output json | jq -r '.Vpcs[0].VpcId')
    if [ $VPC != null ]; then 
        echo "Delete VPC Endpoint"
        export VPCE=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=vpce-$CLUSTER_NAME" --output json | jq -r '.VpcEndpoints[0].VpcEndpointId')
        if [ $VPCE != null ]; then _aws_cmd "delete-vpc-endpoints --vpc-endpoint-ids $VPCE"; fi

        export ELB=$(aws elb describe-load-balancers --output json | jq -r '.LoadBalancerDescriptions[]'| jq -r 'select(.VPCId == '\"${VPC}\"')' | jq -r '.LoadBalancerName')
        if [ $ELB != "" ]; then aws elb delete-load-balancer --load-balancer-name $ELB; fi

        for ZONE in a b c; 
        do
            echo "Delete Subnets and Route tables"
            export PRI_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r '.RouteTables[0].RouteTableId')
            export RT_TB_ASSO_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-table-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r '.RouteTables[0].Associations[0].RouteTableAssociationId')
            export PRI_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Subnets[0].SubnetId")

            if [ $PRI_RT_TB != null ]; then _aws_cmd "delete-route --route-table-id $PRI_RT_TB --destination-cidr-block 0.0.0.0/0"; fi
            if [ $RT_TB_ASSO_ID != null ]; then _aws_cmd "disassociate-route-table --association-id $RT_TB_ASSO_ID"; fi
            if [ $PRI_RT_TB != null ]; then _aws_cmd "delete-route-table --route-table-id $PRI_RT_TB"; fi
            if [ $PRI_SUB != null ]; then _aws_cmd "delete-subnet --subnet-id $PRI_SUB"; fi

            export RT_TB_ASSO_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r '.RouteTables[0].Associations[].RouteTableAssociationId')
            export NGW=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ngw-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".NatGateways[]" | jq -r 'select(.State == "available")' | jq -r ".NatGatewayId")
            export PUB_SUB=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-subnet-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Subnets[0].SubnetId")
            export E_IP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=eip-$CLUSTER_NAME-$AWS_REGION$ZONE" --output json | jq -r ".Addresses[0].AllocationId")

            if [ $RT_TB_ASSO_ID != null ]; then for _id in $RT_TB_ASSO_ID; do _aws_cmd "disassociate-route-table --association-id $_id"; done; fi
            if [ $NGW != null ]; then _aws_cmd "delete-nat-gateway --nat-gateway-id $NGW"; fi
            if [ $PUB_SUB != null ]; then _aws_cmd "delete-subnet --subnet-id $PUB_SUB"; fi
            if [ $E_IP != null ]; then _aws_cmd "release-address --allocation-id $E_IP"; fi
        done

        export PUB_RT_TB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt-table-$CLUSTER_NAME" --output json | jq -r '.RouteTables[0].RouteTableId')
        
        if [ $PUB_RT_TB != null ]; then _aws_cmd "delete-route --route-table-id $PUB_RT_TB --destination-cidr-block 0.0.0.0/0"; fi
        if [ $PUB_RT_TB != null ]; then _aws_cmd "delete-route-table --route-table-id $PUB_RT_TB"; fi

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

_oidc_config(){
    echo "${1} OIDC config, with prefix ${2}"
    if [[ $1 == "create" ]]; then
        echo "${1} OIDC config"
        rosa create oidc-config --mode=auto --managed=false --prefix ${2} -y
        export OIDC_CONFIG=$(rosa list oidc-config | grep ${2} | awk '{print$1}')
    else
        export OIDC_CONFIG=$(rosa list oidc-config | grep ${2} | awk '{print$1}')
        if [ ! -z $OIDC_CONFIG ]; then rosa delete oidc-config --mode=auto --oidc-config-id  ${OIDC_CONFIG} -y || true; fi   # forcing exit 0, as this command may file if it is a shared oidc config
    fi
}

_get_sc_mc_details(){
    if [ -z $SVC_CLUSTER_NAME ]; then
        echo "Find Service Cluster"
        export SVC_CLUSTER_NAME=$(ocm describe cluster ${CLUSTER_NAME} | grep "Service Cluster" | awk '{print$3}')
    fi    
    if [ -z $MGMT_CLUSTER_NAME ]; then
        export MGMT_CLUSTER_NAME=$(ocm describe cluster ${CLUSTER_NAME} | grep "Management Cluster" | awk '{print$3}')
    fi
    echo "Read Management cluster details"
    export MGMT_CLUSTER_DETAILS=$(ocm get /api/clusters_mgmt/v1/clusters | jq -r ".items[]" | jq -r 'select(.name == '\"$MGMT_CLUSTER_NAME\"')')
    export NUMBER_OF_HC=$(cat ${json_file} | jq -r .number_of_hostedcluster)    
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
    export STAGE_CONFIG=""
    export MGMT_CLUSTER_NAME=$(cat ${json_file} | jq -r .staging_mgmt_cluster_name)
    export SVC_CLUSTER_NAME=$(cat ${json_file} | jq -r .staging_svc_cluster_name)
    export STAGE_PROV_SHARD=$(cat ${json_file} | jq -r .staging_mgmt_provisioner_shards)
    export OIDC_PREFIX=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export CLUSTER_NAME="${CLUSTER_NAME}-${HOSTED_ID}" # perf-as3-hcp-1, perf-as3-hcp-2..
    export KUBECONFIG_NAME=$(echo $KUBECONFIG_NAME | awk -F-kubeconfig '{print$1}')-$HOSTED_ID-kubeconfig
    export KUBEADMIN_NAME=$(echo $KUBEADMIN_NAME | awk -F-kubeadmin '{print$1}')-$HOSTED_ID-kubeadmin
    UUID=$(echo $AIRFLOW_CTX_DAG_RUN_ID | base64 | cut -c 1-32 )
    export UUID=${UUID}
    export OCM_CLI_VERSION=$(cat ${json_file} | jq -r .ocm_cli_version)
    if [[ ${OCM_CLI_VERSION} != "container" ]]; then
        OCM_CLI_FORK=$(cat ${json_file} | jq -r .ocm_cli_fork)
        git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
        pushd ocm-cli
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd
    fi    
    if [[ $INSTALL_METHOD == "osd" ]]; then
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
    export OIDC_CONFIG=$(cat ${json_file} | jq -r .oidc_config)
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
        _create_aws_vpc
        echo "Set start time of prom scrape"
        export START_TIME=$(date +"%s")
        if [ $STAGE_PROV_SHARD != "" ]; then
            STAGE_CONFIG="--properties provision_shard_id:${STAGE_PROV_SHARD}"
        fi
        ALL_SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:HostedClusterName,Values=$CLUSTER_NAME" --output json | jq -r ".Subnets[].SubnetId")
        SUBNETS_IDS=""
        for _ID in ${ALL_SUBNETS}; 
        do
            if [[ ${SUBNETS_IDS} == "" ]]; then SUBNETS_IDS=${_ID}; else SUBNETS_IDS=${SUBNETS_IDS}","${_ID};  fi
        done            
        ROSA_HCP_PARAMS="--hosted-cp ${STAGE_CONFIG} --subnet-ids ${SUBNETS_IDS} --machine-cidr 10.0.0.0/16"
        export OIDC_CONFIG=$(rosa list oidc-config | grep $OIDC_PREFIX | awk '{print$1}')
        if [ -z $OIDC_CONFIG ]; then _oidc_config create $OIDC_PREFIX; fi
        ROSA_HCP_PARAMS="${ROSA_HCP_PARAMS} --oidc-config-id ${OIDC_CONFIG}"
        rosa create cluster --tags=User:${GITHUB_USERNAME} --cluster-name ${CLUSTER_NAME} --version "${ROSA_VERSION}" --channel-group=${MANAGED_CHANNEL_GROUP} --compute-machine-type ${COMPUTE_WORKERS_TYPE} --replicas ${COMPUTE_WORKERS_NUMBER} --network-type ${NETWORK_TYPE} ${INSTALLATION_PARAMS} ${ROSA_HCP_PARAMS}
    fi
    postinstall
    return 0
}

postinstall(){
    _wait_for_cluster_ready ${CLUSTER_NAME}
    # sleeping to address issue #324
    sleep 120
    export EXPIRATION_TIME=$(cat ${json_file} | jq -r .rosa_expiration_time)
    _download_kubeconfig "$(_get_cluster_id ${CLUSTER_NAME})" ./kubeconfig
    _get_sc_mc_details
    echo "Index Managment cluster info"
    index_metadata "management"
    _download_kubeconfig "$(ocm list clusters --no-headers --columns id ${MGMT_CLUSTER_NAME})" ./mgmt_kubeconfig
    kubectl delete secret staging-mgmt-cluster-kubeconfig || true
    kubectl create secret generic staging-mgmt-cluster-kubeconfig --from-file=config=./mgmt_kubeconfig

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
        kubectl delete secret ${KUBEADMIN_NAME} || true
        kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    else
        URL=$(rosa describe cluster -c $CLUSTER_NAME --output json | jq -r ".api.url")
        START_TIMER=$(date +%s)      
        PASSWORD=$(rosa create admin -c "$(_get_cluster_id ${CLUSTER_NAME})" -y 2>/dev/null | grep "oc login" | awk '{print $7}')
        CURRENT_TIMER=$(date +%s)
        DURATION=$(($CURRENT_TIMER - $START_TIMER))
        INDEXDATA+=("cluster_admin_create-${DURATION}")  
        kubectl delete secret ${KUBEADMIN_NAME} || true
        kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
        _login_check $URL $PASSWORD
        # set expiration to 24h
        rosa edit cluster -c "$(_get_cluster_id ${CLUSTER_NAME})" --expiration=${EXPIRATION_TIME}m
    fi
    index_metadata "cluster-install"
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
        WORKER_READY_TIME=0
        for i in "${INDEXDATA[@]}" ; do IFS="-" ; set -- $i
            METADATA="${METADATA}, \"$1\":\"$2\""
            if [ $1 != "day2operations" ] && [ $1 != "login" ] ; then
                INSTALL_TIME=$((${INSTALL_TIME} + $2))
            elif [ $1 == "day2operations" ]; then
                WORKER_READY_TIME=$2
            else
                TOTAL_TIME=$2
            fi
        done
        IFS=" "
        METADATA="${METADATA}, \"duration\":\"${INSTALL_TIME}\""
        METADATA="${METADATA}, \"workers_ready\":\"$(($INSTALL_TIME + $WORKER_READY_TIME))\""
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

    unset KUBECONFIG
    return 0
}

index_mgmt_cluster_stat(){
    echo "Indexing Management cluster stat..."
    cd /home/airflow/workspace    
    echo "Installing kube-burner"
    _download_kubeconfig "$(ocm list clusters --no-headers --columns id ${MGMT_CLUSTER_NAME})" ./mgmt_kubeconfig
    export KUBE_BURNER_RELEASE=${KUBE_BURNER_RELEASE:-1.5}
    curl -L https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_RELEASE}/kube-burner-${KUBE_BURNER_RELEASE}-Linux-x86_64.tar.gz -o kube-burner.tar.gz
    sudo tar -xvzf kube-burner.tar.gz -C /usr/local/bin/
    git clone -q -b ${E2E_BENCHMARKING_BRANCH}  ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
    METRIC_PROFILE=/home/airflow/workspace/e2e-benchmarking/workloads/kube-burner-ocp-wrapper/metrics-profiles/mc-metrics.yml
    cat > baseconfig.yml << EOF
---
global:
  indexerConfig:
    esServers: ["${ES_SERVER}"]
    insecureSkipVerify: true
    defaultIndex: ${ES_INDEX}
    type: elastic
EOF

    HCP_NAMESPACE="$(_get_cluster_id ${CLUSTER_NAME})-$CLUSTER_NAME"
    MC_PROMETHEUS=https://$(oc --kubeconfig=./mgmt_kubeconfig get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
    MC_PROMETHEUS_TOKEN=$(oc --kubeconfig=./mgmt_kubeconfig sa new-token -n openshift-monitoring prometheus-k8s)
    Q_NODES=$(curl -H "Authorization: Bearer ${MC_PROMETHEUS_TOKEN}" -k --silent --globoff  ${MC_PROMETHEUS}/api/v1/query?query='sum(kube_node_role{role!~"master|infra|workload|obo"})by(node)&time='$(date +"%s")'' | jq -r '.data.result[].metric.node' | xargs)
    MGMT_WORKER_NODES=${Q_NODES// /|}
    echo "Exporting required vars"
    cat << EOF
MC_PROMETHEUS: ${MC_PROMETHEUS}
MC_PROMETHEUS_TOKEN: <truncated>
HCP_NAMESPACE: ${HCP_NAMESPACE}
MGMT_WORKER_NODES: ${MGMT_WORKER_NODES}
elapsed: "20m:"

EOF
     export MC_PROMETHEUS MC_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES elapsed
    METADATA=$(cat << EOF
{
"uuid":"${UUID}",
"timestamp": "$(date +%s%3N)",
"hostedClusterName": "${HC_INFRASTRUCTURE_NAME}",
"clusterName": "${HC_INFRASTRUCTURE_NAME}",
"mgmtClusterName": "${MGMT_CLUSTER_NAME}"
}
EOF
)
    printf "Indexing metadata to ES"
    curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${ES_INDEX}/_doc -d "${METADATA}" -o /dev/null

    echo "Running kube-burner index.." 
    kube-burner index --uuid=${UUID} --prometheus-url=${MC_PROMETHEUS} --token ${MC_PROMETHEUS_TOKEN} --start=$START_TIME --end=$((END_TIME+600)) --step 2m --metrics-profile ${METRIC_PROFILE}  --config ./baseconfig.yml --log-level debug
    echo "Finished indexing results"
}

cleanup(){
    if [[ $INSTALL_METHOD == "osd" ]]; then
        ocm delete cluster "$(_get_cluster_id ${CLUSTER_NAME})"
        echo "Cluster is getting Uninstalled, deleting OSD access keys now.."
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY_ID || true
    else
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
        _delete_aws_vpc
        if [ -z $OIDC_CONFIG ]; then _oidc_config delete $OIDC_PREFIX; fi
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
        echo "pre-clean AWS resources" 
        _delete_aws_vpc
        install
        export HC_INFRASTRUCTURE_NAME=$(_get_cluster_id ${CLUSTER_NAME})
        index_mgmt_cluster_stat "install-metrics"

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
    _get_sc_mc_details
    cleanup
    index_metadata
    index_mgmt_cluster_stat "destroy-metrics"
    rosa logout
    ocm logout    
fi
