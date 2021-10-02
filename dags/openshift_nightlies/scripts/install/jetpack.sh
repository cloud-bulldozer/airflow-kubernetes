#!/bin/bash

set -o pipefail
set -ex

while getopts j:o: flag
do
    case "${flag}" in
        j) json_file=${OPTARG};;
        o) operation=${OPTARG};;
    esac
done

setup(){
    mkdir /home/airflow/workspace
    cd /home/airflow/workspace
    git clone --depth=1 https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git
    git clone https://github.com/redhat-performance/jetpack.git
    export PUBLIC_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/home/airflow/workspace/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    cd jetpack
    # Create inventory File:
    echo "[orchestration]" > inventory
    echo "${ORCHESTRATION_HOST}" >> inventory

    export ANSIBLE_FORCE_COLOR=true
    cp ci/ocp_jetpack_vars.yml group_vars/all.yml
    cp ci/ocp_install_vars.yml vars/shift_stack_vars.yaml

    # Get the day of week and set networkType as OpenshiftSDN on odd days and kuryr on even days in case no network is defined manually.
    # if [ -z "$OPENSHIFT_NETWORK_TYPE" ]
    # then
    #     DOW=$(date +%u)
    #     rem=$(( $DOW % 2 ))
    #     if [ $rem -eq 0 ]
    #     then
    #         echo "Using kuryr as Network Type"
    #         export OPENSHIFT_NETWORK_TYPE=Kuryr
    #     else
    #         echo "Using OpenshiftSDN as Network Type"
    #         export OPENSHIFT_NETWORK_TYPE=OpenshiftSDN
    #     fi
    # fi
}

run_jetpack(){
    if [[ "$operation" == "install" ]]; then

        printf "Running Cluster Install Steps Using Jetpack"
        if [ $INSTALL_OSP == true ]
        then
            time /home/airflow/.local/bin/ansible-playbook -vv main.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-install.timing
            ssh-copy-id -i ${PUBLIC_KEY} ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST}
        else
            echo "[undercloud]" >> inventory
            echo "${ORCHESTRATION_HOST} ansible_user=${ORCHESTRATION_USER}" >> inventory
            time /home/airflow/.local/bin/ansible-playbook -i inventory -vv delete_single_ocp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-delete-ocp.timing
            time /home/airflow/.local/bin/ansible-playbook -i inventory -vv ocp_on_osp.yml -e platform=osp --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-install-ocp.timing
        fi

        printf "Running post-install Steps Using Scale-ci-deploy"
        git clone --depth=1 https://github.com/cloud-bulldozer/scale-ci-deploy.git
        cd scale-ci-deploy
        # disable openshift install as we already installed via jetpack
        export OPENSHIFT_INSTALL=false
        export DYNAMIC_DEPLOY_PATH=$DEPLOY_PATH
        time /home/airflow/.local/bin/ansible-playbook -i ../inventory -vv OCP-4.X/install-on-osp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-post-install.timing

    elif [[ "$operation" == "cleanup" ]]; then
        printf "Running Cleanup Steps"
        time /home/airflow/.local/bin/ansible-playbook -i inventory -vv delete_single_ocp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-delete-ocp.timing
    fi
}

post_install(){
    # ssh -o StrictHostKeyChecking=no ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat $DEPLOY_PATH/.openshift_install.log"
    # printenv

    _kubeadmin_password=$(ssh -o StrictHostKeyChecking=no ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat $DEPLOY_PATH/auth/kubeadmin-password")

    # Copy kubeconfig on the pod
    ssh -o StrictHostKeyChecking=no ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST} -i ${PRIVATE_KEY} "cat $DEPLOY_PATH/auth/kubeconfig" > kubeconfig

    kubectl create secret generic ${KUBEADMIN_NAME} --from-literal=KUBEADMIN_PASSWORD=$_kubeadmin_password
    kubectl create secret generic ${KUBECONFIG_NAME} --from-file=config=kubeconfig
}

cleanup(){
    kubectl delete secret ${KUBEADMIN_NAME} || true
    kubectl delete secret ${KUBECONFIG_NAME} || true
}


setup
run_jetpack

if [[ "$operation" == "install" ]]; then
    printf "Running Post Install Steps"
    cleanup
    post_install

elif [[ "$operation" == "cleanup" ]]; then
    printf "Running Cleanup Steps"
fi
