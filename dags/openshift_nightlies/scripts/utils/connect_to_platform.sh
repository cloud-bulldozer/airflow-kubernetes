#!/bin/bash
set -eux
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

generate_external_labels(){
    # Get OpenShift cluster details
    export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export OPENSHIFT_VERSION=$(oc version -o json | jq -r '.openshiftVersion')
    export NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.status.networkType}')
    export PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    export DAG_ID=${AIRFLOW_CTX_DAG_ID}

}

cleanup_old_resources(){
    if [[ $(oc get project | grep grafana-agent) ]]; then
        echo "Delete existing grafana resources and namespace"
        oc delete project grafana-agent --force
        # wait for few sec to finish deleting
        sleep 80
    fi
    if [[ $(oc get project | grep loki) ]]; then
        echo "Delete existing loki resources and namespace"
        oc delete project loki --force
        # wait for few sec to finish deleting
        sleep 80
    fi  
}

install_grafana_agent(){
    envsubst < $SCRIPT_DIR/templates/grafana-agent.yaml | kubectl apply -f -
}

install_promtail(){
    helm repo add grafana https://grafana.github.io/helm-charts 
    helm repo update
    oc create namespace loki || true
    oc adm policy add-scc-to-group privileged system:authenticated
    envsubst < $SCRIPT_DIR/templates/promtail-values.yaml | helm upgrade --install promtail --namespace=loki grafana/promtail -f - 
}


setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    cp /home/airflow/auth/config /home/airflow/workspace/config
    export KUBECONFIG=/home/airflow/workspace/config
    curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc
    export PATH=$PATH:$(pwd)
    if [[ $(oc get nodes | grep -c worker) -lt 1 ]]; then 
        echo "No worker nodes to install grafana agent"
        exit 0 # exiting without failing the job.
    fi
}

bm_setup(){
    echo "Baremetal connector.."
    echo "Orchestration host --> $ORCHESTRATION_HOST"

    git clone https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
    export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    echo "Transfering the environment variables to the orchestration host"
    mkdir /tmp/${AIRFLOW_CTX_DAG_ID}
    env >> /tmp/environment_new.txt
    cp $SCRIPT_DIR/templates/grafana-agent.yaml /tmp/${AIRFLOW_CTX_DAG_ID}
    cp $SCRIPT_DIR/templates/promtail-values.yaml /tmp/${AIRFLOW_CTX_DAG_ID}
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} -r /tmp/environment_new.txt root@${ORCHESTRATION_HOST}:/tmp/
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} -r /tmp/${AIRFLOW_CTX_DAG_ID} root@${ORCHESTRATION_HOST}:/tmp/

    ssh -t -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} << 'EOF'
    export KUBECONFIG=/home/kni/clusterconfigs/auth/kubeconfig
    while read line; do export $line; done < /tmp/environment_new.txt
    # clean up the temporary environment file
    rm -rf /tmp/environment_new.txt

    # Get OpenShift cluster details
    export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export OPENSHIFT_VERSION=$(oc version -o json | jq -r '.openshiftVersion')
    export NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.status.networkType}')
    export PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    export DAG_ID=${AIRFLOW_CTX_DAG_ID}
    
    # Install grafana agent
    if [[ $(oc get project | grep grafana-agent) ]]; then
        echo "Delete existing resources and namespace"
        oc delete project grafana-agent --force
        # wait for few sec to finish deleting
        sleep 15
    fi
    envsubst < /tmp/${AIRFLOW_CTX_DAG_ID}/grafana-agent.yaml | kubectl apply -f -
    
    # Install Helm
    cd /tmp/${AIRFLOW_CTX_DAG_ID}/
    curl https://get.helm.sh/helm-v3.5.2-linux-386.tar.gz -o helm-v3.5.2-linux-386.tar.gz
    tar -xf helm-v3.5.2-linux-386.tar.gz
    cp linux-386/helm /usr/local/bin --update

    # Install promtail
    if [[ $(oc get project | grep loki) ]]; then
        echo "Delete existing resources and namespace"
        oc delete project loki --force
        # wait for few sec to finish deleting
        sleep 15
    fi    
    helm repo add grafana https://grafana.github.io/helm-charts 
    helm repo update
    oc create namespace loki || true
    oc adm policy add-scc-to-group privileged system:authenticated
    envsubst < /tmp/${AIRFLOW_CTX_DAG_ID}/promtail-values.yaml | helm upgrade --install promtail --namespace=loki grafana/promtail -f - 

EOF
    if [[ $? != 0 ]]; then
        exit 1
    fi
}

if [[ $REL_PLATFORM == "baremetal" ]]; then
    bm_setup
else
    setup
    cleanup_old_resources
    generate_external_labels
    install_grafana_agent
    install_promtail
fi
