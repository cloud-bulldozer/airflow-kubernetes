#!/bin/bash

export UUID=$(uuidgen | head -c8)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')
echo "############################################"
echo "# Benchmark UUID: ${UUID}"
echo "############################################"

env >> /tmp/environment.txt
echo $UUID

run_ocm_benchmark(){
    echo "OCM Benchmark will be begin.."
    echo "Orchestration host --> $ORCHESTRATION_HOST"

    git clone -q --depth=1 --single-branch --branch master https://${SSHKEY_TOKEN}@github.com/redhat-performance/perf-dept.git /tmp/perf-dept
    export PUBLIC_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2.pub
    export PRIVATE_KEY=/tmp/perf-dept/ssh_keys/id_rsa_pbench_ec2
    chmod 600 ${PRIVATE_KEY}

    echo "Transfering the environment variables and OCM test config file to the orchestration host"
    scp -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY}  /tmp/environment.txt root@${ORCHESTRATION_HOST}:/tmp/environment_new.txt

    echo "Running ocm-load-test inside $ORCHESTRATION_HOST"
    ssh -t -o 'ServerAliveInterval=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' -i ${PRIVATE_KEY} root@${ORCHESTRATION_HOST} << EOF

    echo "Cleanup previous UUIDs"
    rm -rf /tmp/*api-load*
    mkdir /tmp/${UUID}
    git clone --single-branch --branch ci_test https://github.com/venkataanil/ocm-api-load /tmp/${UUID}
    cd /tmp/${UUID}
    echo "Building the binary"
    go mod download
    make

    cat /tmp/environment_new.txt | awk -v x="'" -F "=" '{print "export " \$1"="x\$2x}' > vars.sh
    source vars.sh
    echo "cat /tmp/environment_new.txt"
    cat /tmp/environment_new.txt
    rm -rf /tmp/environment_new.txt vars.sh

    echo "Clean-up existing OSD access keys.."
    AWS_KEY=$(aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId')
    LEN_AWS_KEY=`echo $AWS_KEY | wc -w`
    if [[  ${LEN_AWS_KEY} -eq 2 ]]; then
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id `printf ${AWS_KEY[0]}`
    fi
    echo "Creating aws key with admin user for OCM testing"
    admin_key=\$(/usr/bin/aws iam create-access-key --user-name OsdCcsAdmin --output json)
    export AWS_ACCESS_KEY_ID=\$(echo \$admin_key | jq -r '.AccessKey.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=\$(echo \$admin_key | jq -r '.AccessKey.SecretAccessKey')
    sleep 60

    echo "Preparing config files"
    envsubst < /tmp/${UUID}/ci/templates/config.yaml > /tmp/${UUID}/config.yaml
    export KUBE_ES_INDEX=ocm-uhc-acct-mngr
    envsubst < /tmp/${UUID}/ci/templates/kube-burner-config.yaml > /tmp/${UUID}/kube-burner-am-config.yaml
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    envsubst < /tmp/${UUID}/ci/templates/kube-burner-config.yaml > /tmp/${UUID}/kube-burner-cs-config.yaml

    start_time=\$(date +%s)
    echo "Running the ocm-load-test test"
    build/ocm-load-test --config-file config.yaml &> ${UUID}_ocm-load-test
    cp ${UUID}_ocm-load-test /tmp/${UUID}/results/${UUID}_ocm-load-test.json

    end_time=\$(date +%s)

    echo "Uploading Result files..."
    python3 automation.py upload --dir /tmp/${UUID}/results --server ${SNAPPY_DATA_SERVER_URL} --user ${SNAPPY_DATA_SERVER_USERNAME} --password ${SNAPPY_DATA_SERVER_PASSWORD};

    curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz
    echo "Running kube-burner index to scrap metrics from UHC account manager service from \${start_time} to \${end_time} and push to ES"
    ./kube-burner index -c kube-burner-am-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=ci/templates/metrics_acct_mgmr.yaml --start \$start_time --end \$end_time
    echo "UHC account manager Metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "Running kube-burner index to scrap metrics from UHC clusters service from \${start_time} to \${end_time} and push to ES"
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    ./kube-burner index -c kube-burner-cs-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=ci/templates/metrics_clusters_service.yaml --start \$start_time --end \$end_time
    echo "UHC clusters service metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "Removing configuration files"
    rm -f /tmp/${UUID}/config.yaml
    rm -f /tmp/${UUID}/kube-burner-am-config.yaml
    rm -f /tmp/${UUID}/kube-burner-cs-config.yaml

    echo "converting start and end times into milliseconds"
    start_time=\$(expr \$start_time \* 1000)
    end_time=\$(expr \$end_time \* 1000)

    echo "Results URLs"
    echo "Account Manager Dashboard https://admin:100yard-@grafana.apps.observability.perfscale.devcluster.openshift.com/d/uhc-account-manager/uhc-account-manager?orgId=1&var-uuid=${UUID}&var-datasource=ocm-uhc-acct-mngr&from=\$start_time&to=\$end_time"
    echo "Clusters Service Dashboard https://admin:100yard-@grafana.apps.observability.perfscale.devcluster.openshift.com/d/uhc-clusters-service/uhc-clusters-service?orgId=1&var-datasource=ocm-uhc-clusters-service&var-uuid=${UUID}&from=\$start_time&to=\$end_time"
EOF

}

run_ocm_benchmark
