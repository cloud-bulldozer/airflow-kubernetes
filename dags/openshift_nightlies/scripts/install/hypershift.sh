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
    export HOSTED_CLUSTER_NAME=hyp-$MGMT_CLUSTER_NAME-$HOSTED_NAME
    export HOSTED_KUBECONFIG_NAME=$(echo $KUBECONFIG_NAME | awk -F-kubeconfig '{print$1}')-$HOSTED_NAME-kubeconfig
    export HOSTED_KUBEADMIN_NAME=$(echo $KUBEADMIN_NAME | awk -F-kubeadmin '{print$1}')-$HOSTED_NAME-kubeadmin    
    export KUBECONFIG=/home/airflow/auth/config
    export HC_EXTERNAL_DNS=$(cat ${json_file} | jq -r .hc_external_dns)
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
        ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
        ocm whoami
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
    fi
    export HYPERSHIFT_CLI_VERSION=$(cat ${json_file} | jq -r .hypershift_cli_version)
    if [[ ${HYPERSHIFT_CLI_VERSION} != "container" ]]; then
        HYPERSHIFT_CLI_FORK=$(cat ${json_file} | jq -r .hypershift_cli_fork)
        echo "Remove current Hypershift CLI directory.."
        sudo rm -rf hypershift
        sudo rm /usr/local/bin/hypershift || true
        git clone -q --depth=1 --single-branch --branch ${HYPERSHIFT_CLI_VERSION} ${HYPERSHIFT_CLI_FORK}    
        pushd hypershift
        make build
        sudo cp bin/hypershift /usr/local/bin
        popd
    fi
    export MGMT_BASEDOMAIN=$(_get_base_domain $(_get_cluster_id ${MGMT_CLUSTER_NAME}))
    export MGMT_AWS_HZ_ID=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${MGMT_BASEDOMAIN}'.")' | jq -r '.Id')
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        echo "Create external DNS for this iteration.."
        export BASEDOMAIN=hyp.${MGMT_BASEDOMAIN}
        AWS_HZ=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${BASEDOMAIN}'.")')
        if [[ ${AWS_HZ} == "" ]]; then
            AWS_HZ_ID=$(aws route53 create-hosted-zone --name $BASEDOMAIN --caller-reference ${HOSTED_CLUSTER_NAME}-$(echo $(uuidgen) | cut -c 1-5) | jq -r '.HostedZone.Id')
            DS_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $AWS_HZ_ID  | jq -r '.ResourceRecordSets[] | select(.Name=="'"$BASEDOMAIN"'.") | select(.Type=="NS")' | jq -c '.ResourceRecords')
            aws route53 change-resource-record-sets --hosted-zone-id  $MGMT_AWS_HZ_ID \
                --change-batch '{ "Comment": "Creating a record set" , "Changes": [{"Action": "CREATE", "ResourceRecordSet": {"Name": "'"$BASEDOMAIN"'", "Type": "NS", "TTL": 300, "ResourceRecords" : '"$DS_VALUE"'}}]}'
        fi
    else
        export BASEDOMAIN=${MGMT_BASEDOMAIN}
    fi
    echo [default] >> aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> aws_credentials
    echo "MANAGEMENT CLUSTER VERSION:"
    ocm list cluster $MGMT_CLUSTER_NAME
    echo "MANAGEMENT CLUSTER NODES:"
    kubectl get nodes
}

install(){
    export HYPERSHIFT_OPERATOR_IMAGE=$(cat ${json_file} | jq -r .hypershift_operator_image)
    export HCP_PLATFORM_MONITORING=$(cat ${json_file} | jq -r .hcp_platform_monitoring)
    HO_IMAGE_ARG=""
    HCP_P_MONITOR=""
    EXT_DNS_ARG=""
    if [[ $HYPERSHIFT_OPERATOR_IMAGE != "" ]]; then
        HO_IMAGE_ARG="--hypershift-image $HYPERSHIFT_OPERATOR_IMAGE"
    fi
    if [[ $HCP_PLATFORM_MONITORING == "true" ]]; then
        HCP_P_MONITOR="--platform-monitoring $HCP_PLATFORM_MONITORING"
    fi
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-provider=aws --external-dns-credentials=aws_credentials --external-dns-domain-filter=$BASEDOMAIN"
    fi
    echo "Create S3 bucket.."
    aws s3api create-bucket \
        --acl public-read \
        --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org \
        --create-bucket-configuration LocationConstraint=$AWS_REGION \
        --region $AWS_REGION || true
    echo "Wait till S3 bucket is ready.."
    aws s3api wait bucket-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org 
    hypershift install  \
        --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org \
        --oidc-storage-provider-s3-credentials aws_credentials \
        --oidc-storage-provider-s3-region $AWS_REGION \
        --metrics-set All $EXT_DNS_ARG $HCP_P_MONITOR $HO_IMAGE_ARG

    echo "Wait till Operator is ready.."
    kubectl wait --for=condition=available --timeout=600s deployments/operator -n hypershift
}

create_cluster(){
    echo "Create Hosted cluster.."    
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_instance_type)
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_network_type)
    export CONTROLPLANE_REPLICA_TYPE=$(cat ${json_file} | jq -r .hosted_control_plane_availability)
    export INFRA_REPLICA_TYPE=$(cat ${json_file} | jq -r .hosted_infra_availability)
    export CPO_IMAGE=$(cat ${json_file} | jq -r .control_plane_operator_image)
    export RELEASE_IMAGE=$(cat ${json_file} | jq -r .hosted_cluster_release_image)
    export HC_MULTI_AZ=$(cat ${json_file} | jq -r .hc_multi_az)
    echo $PULL_SECRET > pull-secret
    CPO_IMAGE_ARG=""
    if [[ $CPO_IMAGE != "" ]] ; then
        CPO_IMAGE_ARG="--control-plane-operator-image=$CPO_IMAGE"
    fi
    RELEASE=""
    if [[ $RELEASE_IMAGE != "" ]]; then
        RELEASE="--release-image=$RELEASE_IMAGE"
    fi
    ZONES=""
    if [[ $HC_MULTI_AZ == "true" ]]; then
        ZONES="--zones ${AWS_REGION}a,${AWS_REGION}b,${AWS_REGION}c"
    fi
    EXT_DNS_ARG=""
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-domain=$BASEDOMAIN"
    fi    
    hypershift create cluster aws \
        --name $HOSTED_CLUSTER_NAME \
        --additional-tags "User=${GITHUB_USERNAME},mgmt-cluster=${MGMT_CLUSTER_NAME}" \
        --node-pool-replicas=$COMPUTE_WORKERS_NUMBER \
        --base-domain $BASEDOMAIN \
        --pull-secret pull-secret \
        --aws-creds aws_credentials \
        --region $AWS_REGION \
        --control-plane-availability-policy $CONTROLPLANE_REPLICA_TYPE \
        --infra-availability-policy $INFRA_REPLICA_TYPE \
        --network-type $NETWORK_TYPE \
        --instance-type $COMPUTE_WORKERS_TYPE \
        --endpoint-access=Public ${EXT_DNS_ARG} ${RELEASE} ${CPO_IMAGE_ARG} ${ZONES}

    echo "Wait till hosted cluster got created and in progress.."
    kubectl wait --for=condition=available=false --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    kubectl get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    echo "Wait till hosted cluster is ready.."
    kubectl wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    postinstall
    update_fw
}

create_empty_cluster(){
    echo "Create None type Hosted cluster.."    
    export NETWORK_TYPE=$(cat ${json_file} | jq -r .hosted_cluster_network_type)
    export CONTROLPLANE_REPLICA_TYPE=$(cat ${json_file} | jq -r .hosted_control_plane_availability)
    export INFRA_REPLICA_TYPE=$(cat ${json_file} | jq -r .hosted_infra_availability)
    echo $PULL_SECRET > pull-secret
    CPO_IMAGE_ARG=""
    if [[ $CPO_IMAGE != "" ]] ; then
        CPO_IMAGE_ARG="--control-plane-operator-image=$CPO_IMAGE"
    fi
    EXT_DNS_ARG=""
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-domain=$BASEDOMAIN"
    fi   
    hypershift create cluster none --name $HOSTED_CLUSTER_NAME \
        --node-pool-replicas=0 \
        --base-domain $BASEDOMAIN \
        --pull-secret pull-secret \
        --control-plane-availability-policy $CONTROLPLANE_REPLICA_TYPE \
        --infra-availability-policy $INFRA_REPLICA_TYPE \
        --network-type $NETWORK_TYPE \
        --endpoint-access=Public ${EXT_DNS_ARG} ${CPO_IMAGE_ARG}
    echo "Wait till hosted cluster got created and in progress.."
    kubectl wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    kubectl get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    echo "Wait till hosted cluster is ready.."
    kubectl wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    postinstall
}

postinstall(){
    echo "Create Hosted cluster secrets for benchmarks.."
    kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-admin-kubeconfig -o json | jq -r '.data.kubeconfig' | base64 -d > ./kubeconfig
    PASSWORD=""
    itr=0
    while [[ $PASSWORD == "" ]]
    do
        PASSWORD=$(kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-kubeadmin-password -o json | jq -r '.data.password' | base64 -d || true)
        itr=$((itr+1))
        if [ $itr -gt 10 ]; then
            echo "Kubeadmin Password is still not set, continue next step.."
            break
        fi
        sleep 30
    done
    unset KUBECONFIG # Unsetting Management cluster kubeconfig, will fall back to Airflow cluster kubeconfig
    kubectl delete secret $HOSTED_KUBECONFIG_NAME $HOSTED_KUBEADMIN_NAME || true
    kubectl create secret generic $HOSTED_KUBECONFIG_NAME --from-file=config=./kubeconfig
    kubectl create secret generic $HOSTED_KUBEADMIN_NAME --from-literal=KUBEADMIN_PASSWORD=${PASSWORD}
    echo "Wait till Hosted cluster is ready.."
    export KUBECONFIG=./kubeconfig
    export NODEPOOL_SIZE=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)
    if [ "${NODEPOOL_SIZE}" == "0" ] ; then
        echo "None type cluster with nodepool size set to 0"
    else
        if [[ $HC_MULTI_AZ == "true" ]]; then
            COMPUTE_WORKERS_NUMBER=$((3*$COMPUTE_WORKERS_NUMBER))
        fi
        itr=0
        while [ $itr -lt 12 ]
        do
            node=$(oc get nodes | grep worker | grep -i ready | grep -iv notready | wc -l)
            if [[ $node == $COMPUTE_WORKERS_NUMBER ]]; then
                echo "All nodes are ready in cluster - $HOSTED_CLUSTER_NAME ..."
                break
            else
                echo "Available node(s) are $node, still waiting for remaining nodes"
                sleep 300
            fi
            itr=$((itr+1))
        done
        if [[ $node != $COMPUTE_WORKERS_NUMBER ]]; then
            echo "All nodes are not ready in cluster - $HOSTED_CLUSTER_NAME ..."
            exit 1
        fi
    fi
}

update_fw(){
    echo "Get AWS VPC and security groups.."
    CLUSTER_VPC=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PrivateIpAddress,PublicIpAddress, PrivateDnsName, VpcId]' --output text | column -t | grep ${HOSTED_CLUSTER_NAME} | awk '{print $7}' | grep -v '^$' | sort -u)
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${CLUSTER_VPC}" --output json | jq -r .SecurityGroups[].GroupId)
    for group in $SECURITY_GROUPS
    do
        echo "Add rules to group $group.."
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 22 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 2022 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 20000-31000 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol udp --port 20000-31000 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 32768-60999 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol udp --port 32768-60999 --cidr 0.0.0.0/0
    done
}

index_mgmt_cluster_stat(){
    echo "Indexing Management cluster stat..."
    cd /home/airflow/workspace    
    echo "Installing kube-burner"
    export KUBE_BURNER_RELEASE=${KUBE_BURNER_RELEASE:-0.16}
    curl -L https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_RELEASE}/kube-burner-${KUBE_BURNER_RELEASE}-Linux-x86_64.tar.gz -o kube-burner.tar.gz
    sudo tar -xvzf kube-burner.tar.gz -C /usr/local/bin/
    echo "Cloning ${E2E_BENCHMARKING_REPO} from branch ${E2E_BENCHMARKING_BRANCH}"
    git clone -q -b ${E2E_BENCHMARKING_BRANCH}  ${E2E_BENCHMARKING_REPO} --depth=1 --single-branch
    export KUBECONFIG=/home/airflow/auth/config
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export HOSTED_CLUSTER_NS="clusters-$HOSTED_CLUSTER_NAME"
    envsubst < /home/airflow/workspace/e2e-benchmarking/workloads/kube-burner/metrics-profiles/hypershift-metrics.yaml > hypershift-metrics.yaml
    envsubst < /home/airflow/workspace/e2e-benchmarking/workloads/kube-burner/workloads/managed-services/baseconfig.yml > baseconfig.yml
    echo "Running kube-burner index.." 
    kube-burner index --uuid=$(uuidgen) --prometheus-url=${PROM_URL} --start=$START_TIME --end=$END_TIME --step 2m --metrics-profile hypershift-metrics.yaml --config baseconfig.yml
    echo "Finished indexing results"
}

cleanup(){
    if [[ $HOSTED_NAME == "operator" ]]; then
        echo "Re-checking Hosted Clusters if any..."
        LIST_OF_HOSTED_CLUSTER=$(kubectl get hostedcluster -n clusters --no-headers | awk '{print$1}')
        export NODEPOOL_SIZE=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)    
        for h in $LIST_OF_HOSTED_CLUSTER
        do
            echo "Destroy Hosted cluster $h ..."
            if [ "${NODEPOOL_SIZE}" == "0" ] ; then
                hypershift destroy cluster none --name $h
            else
                hypershift destroy cluster aws --name $h --aws-creds aws_credentials --region $AWS_REGION
            fi
            sleep 5 # pause a few secs before destroying next...
        done
        echo "Delete AWS s3 bucket..."
        for o in $(aws s3api list-objects --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org | jq -r '.Contents[].Key' | uniq)
        do 
            aws s3api delete-object --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --key=$o || true
        done    
        aws s3api delete-bucket --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org || true
        aws s3api wait bucket-not-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org || true
        sleep 10
        echo "Delete external dns records and hostedzone"
        ROUTE_ID=$(aws route53 list-hosted-zones --output text --query HostedZones | grep $BASEDOMAIN | grep hyp | grep -v terraform | awk '{print$2}')
        for _ID in $ROUTE_ID; 
        do
            aws route53 list-resource-record-sets --hosted-zone-id $_ID --output json | jq -c '.ResourceRecordSets[]' |
            while read -r resourcerecordset; do
                read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
                if [ $type != "NS" -a $type != "SOA" ]; then
                    aws route53 change-resource-record-sets --hosted-zone-id $_ID \
                        --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":'"$resourcerecordset"'}]}' \
                        --output text --query 'ChangeInfo.Id'
                fi
            done
            aws route53 delete-hosted-zone --id=$_ID || true
        done
        if [[ $HC_EXTERNAL_DNS == "true" ]]; then
            echo "Delete recordset in mgmt hostedzone"
            RS_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $MGMT_AWS_HZ_ID | jq -c '.ResourceRecordSets[] | select(.Name=="'"$BASEDOMAIN"'.") | select(.Type=="NS")')
            aws route53 change-resource-record-sets --hosted-zone-id $MGMT_AWS_HZ_ID \
                --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"$RS_VALUE"'}]}' \
                --output text --query 'ChangeInfo.Id'
        fi
        echo "Delete hypershift namespace.."
        oc delete project hypershift clusters --force
    else
        echo "Cleanup Hosted Cluster..."
        export NODEPOOL_SIZE=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)    
        echo "Destroy Hosted cluster $HOSTED_CLUSTER_NAME ..."
        if [ "${NODEPOOL_SIZE}" == "0" ] ; then
            hypershift destroy cluster none --name $HOSTED_CLUSTER_NAME
        else
            hypershift destroy cluster aws --name $HOSTED_CLUSTER_NAME --aws-creds aws_credentials --region $AWS_REGION --destroy-cloud-resources
        fi
    fi
}

export INSTALL_METHOD=$(cat ${json_file} | jq -r .cluster_install_method)
setup
export HC_INTERVAL=$(cat ${json_file} | jq -r .hc_install_interval)
SKEW_FACTOR=$(echo $HOSTED_NAME|awk -F- '{print$2}')
sleep $(($HC_INTERVAL*$SKEW_FACTOR))
echo "Set start time of prom scrape"
export START_TIME=$(date +"%s")

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
        export NODEPOOL_SIZE=$(cat ${json_file} | jq -r .hosted_cluster_nodepool_size)
        if [ "${NODEPOOL_SIZE}" == "0" ] ; then
            create_empty_cluster
        else
            create_cluster
        fi
    else
        printf "INFO: Cluster ${MGMT_CLUSTER_NAME} already installed but not ready, exiting..."
	    exit 1
    fi
    echo "Set end time of prom scrape"
    export END_TIME=$(date +"%s")
    index_mgmt_cluster_stat
fi
