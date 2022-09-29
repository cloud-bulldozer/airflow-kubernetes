#!/bin/bash
# shellcheck disable=SC2155
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

_get_cluster_status(){
    az aro list --resource-group ${AZ_RESOURCEGROUP} --output json --query ['[].provisioningState'] | jq .[] | jq .[]
}

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    export PATH=$PATH:/usr/bin:/usr/local/go/bin
    export HOME=/home/airflow
    export AZ_LOCATION=centralus
    export AZ_CLUSTERNAME=$(cat ${json_file} | jq -r .openshift_cluster_name)
    export AZ_USERNAME=$(cat ${json_file} | jq -r .aro_username)
    export AZ_TENANT=$(cat ${json_file} | jq -r .aro_tenant)
    export COMPUTE_WORKERS_NUMBER=$(cat ${json_file} | jq -r .openshift_worker_count)
    export COMPUTE_WORKERS_TYPE=$(cat ${json_file} | jq -r .openshift_worker_instance_type)
    export AZ_RESOURCEGROUP=${AZ_RESOURCEGROUP:-${AZ_CLUSTERNAME}-rg}

    echo "INFO: Updating OCP Pull Secret..."
    cat ${json_file} | jq -r .openshift_install_pull_secret > pull-secret.txt
    cat ./pull-secret.txt

    echo ${AZ_MANAGED_SERVICES_TOKEN} | sed -e 's$\\n$\n$g' > ./PerfScaleManagedServices.pem
    cat ./PerfScaleManagedServices.pem

    echo "INFO: Login via Azure-cli..."
    az login --service-principal --username ${AZ_USERNAME} --password ./PerfScaleManagedServices.pem --tenant ${AZ_TENANT}

    echo "INFO: Get details of the subscription..."
    az account show
    oc version --client

    echo "INFO: Checking the current Subscription Quota..."
    az vm list-usage -l ${AZ_LOCATION} --query "[?contains(name.value, 'standardDSv3Family')]" -o table
}

install(){
    echo "INFO: Creating a virtual network..."
    az network vnet create --resource-group ${AZ_RESOURCEGROUP} --name ${AZ_CLUSTERNAME}-vnet --address-prefixes 10.0.0.0/22

    echo "INFO: Creating an empty subnet for the Master nodes..."
    az network vnet subnet create --resource-group ${AZ_RESOURCEGROUP} --vnet-name ${AZ_CLUSTERNAME}-vnet --name ${AZ_CLUSTERNAME}-master-subnet --address-prefixes 10.0.0.0/23 --service-endpoints Microsoft.ContainerRegistry

    echo "INFO: Creating an empty subnet for the Worker nodes..."
    az network vnet subnet create --resource-group ${AZ_RESOURCEGROUP} --vnet-name ${AZ_CLUSTERNAME}-vnet --name ${AZ_CLUSTERNAME}-worker-subnet --address-prefixes 10.0.2.0/23 --service-endpoints Microsoft.ContainerRegistry

    echo "INFO: Disable subnet private endpoint policies..."
    az network vnet subnet update --name ${AZ_CLUSTERNAME}-master-subnet --resource-group ${AZ_RESOURCEGROUP} --vnet-name ${AZ_CLUSTERNAME}-vnet --disable-private-link-service-network-policies true

    echo "INFO: Creating the cluster..."
    # Add tags to the cluster creation for better "cloud-management"
    az aro create cluster --resource-group ${AZ_RESOURCEGROUP} --name ${AZ_CLUSTERNAME} --vnet ${AZ_CLUSTERNAME}-vnet --master-subnet ${AZ_CLUSTERNAME}-master-subnet --worker-subnet ${AZ_CLUSTERNAME}-worker-subnet --pull-secret @pull-secret.txt
    postinstall
}

postinstall(){
    KUBE_PASSWORD={az aro list-credentials --resource-group ${AZ_RESOURCEGROUP} --name ${AZ_CLUSTERNAME} | jq -r [.kubeadminPassword]}

    echo "INFO: Retrieving ${AZ_CLUSTERNAME}'s API Server Address..."
    API_SERVER_URL=${az aro show --name ${AZ_CLUSTERNAME} --resource-group ${AZ_RESOURCEGROUP} --query "apiserverProfile.url" -o tsv}

    echo "INFO: Retrieving ${AZ_CLUSTERNAME}'s Web Console URL..."
    az aro show --name ${AZ_CLUSTERNAME} --resource-group ${AZ_RESOURCEGROUP} --query "consoleProfile.url" -o tsv

    unset KUBECONFIG
    kubectl delete secret ${KUBECONFIG_NAME} || true
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=${KUBE_PASSWORD}

    echo "INFO: Login to OCP"
    oc login -u kubeadmin -p ${KUBE_PASSWORD} ${API_SERVER_URL} --insecure-skip-tls-verify=false
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=./kubeconfig

}


cleanup(){
    echo "INFO: Cleanup ${AZ_CLUSTERNAME} ARO Cluster..."
    az aro delete --resource-group ${AZ_RESOURCEGROUP} --name ${AZ_CLUSTERNAME} --yes
    return 0
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
    printf "INFO: Cleanup ARO Steps"
    cleanup        
fi
