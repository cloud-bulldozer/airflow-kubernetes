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
    ansible --version
    cp ci/ocp_jetpack_vars.yml group_vars/all.yml
    cp ci/ocp_install_vars.yml vars/shift_stack_vars.yaml

    # Get the day of week and set networkType as OpenshiftSDN on odd days and kuryr on even days in case no network is defined manually.
    if [ -z "$OPENSHIFT_NETWORK_TYPE" ]
    then
        DOW=$(date +%u)
        rem=$(( $DOW % 2 ))
        if [ $rem -eq 0 ]
        then
            echo "Using kuryr as Network Type"
            export OPENSHIFT_NETWORK_TYPE=Kuryr
        else
            echo "Using OpenshiftSDN as Network Type"
            export OPENSHIFT_NETWORK_TYPE=OpenshiftSDN
        fi
    fi
}

run_jetpack(){
    if [[ "$operation" == "install" ]]; then

        printf "Running Cluster Install Steps Using Jetpack"
        if [ $INSTALL_OSP == true ]
        then
            time ansible-playbook -vvv main.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-install.timing
            ssh-copy-id -i ${PUBLIC_KEY} ${ORCHESTRATION_USER}@${ORCHESTRATION_HOST}
        else
            echo "[undercloud]" >> inventory
            echo "${ORCHESTRATION_HOST} ansible_user=${ORCHESTRATION_USER}" >> inventory
            time ansible-playbook -i inventory -vvv delete_single_ocp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-delete-ocp.timing
            time ansible-playbook -i inventory -vvv ocp_on_osp.yml -e platform=osp --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-install-ocp.timing
        fi

        printf "Running post-install Steps Using Scale-ci-deploy"
        git clone --depth=1 https://github.com/cloud-bulldozer/scale-ci-deploy.git
        cd scale-ci-deploy
        # disable openshift install as we already installed via jetpack
        export OPENSHIFT_INSTALL=false
        export DYNAMIC_DEPLOY_PATH=$OPENSHIFT_CLUSTER_NAME
        time ansible-playbook -i ../inventory -vvv OCP-4.X/install-on-osp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-post-install.timing

    elif [[ "$operation" == "cleanup" ]]; then
        printf "Running Cleanup Steps"
        time ansible-playbook -i inventory -vvv delete_single_ocp.yml --extra-vars "@${json_file}" | tee $(date +"%Y%m%d-%H%M%S")-jetpack-delete-ocp.timing
    fi
}

setup
run_jetpack
