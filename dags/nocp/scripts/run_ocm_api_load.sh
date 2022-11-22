#!/bin/bash

set -x

run_ocm_api_load(){
    echo "Cleanup previous UUIDs"
    cd ~/
    export $(cat environment.txt | xargs)
    export UUID=$(uuidgen | head -c8)-$AIRFLOW_CTX_TASK_ID-$(date '+%Y%m%d')
    echo "# Benchmark UUID: ${UUID}"
    rm -rf ocm-api-load
    git clone https://github.com/cloud-bulldozer/ocm-api-load
    cd ocm-api-load
    echo "Building the binary"
    go mod download
    make


    echo "Clean-up existing OSD access keys.."
    AWS_KEY=$(/usr/bin/aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId')
    LEN_AWS_KEY=$(echo $AWS_KEY | wc -w)
    if [[  ${LEN_AWS_KEY} -eq 2 ]]; then
	/usr/bin/aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $(printf ${AWS_KEY[0]})
    fi
    echo "Creating aws key with admin user for OCM testing"
    admin_key=$(/usr/bin/aws iam create-access-key --user-name OsdCcsAdmin --output json)
    export AWS_ACCESS_KEY_ID=$(echo $admin_key | jq -r '.AccessKey.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $admin_key | jq -r '.AccessKey.SecretAccessKey')
    sleep 60

    echo "Preparing config files"
    envsubst < ci/templates/config.yaml > config.yaml
    export KUBE_ES_INDEX=ocm-uhc-acct-mngr
    envsubst < ci/templates/kube-burner-config.yaml > kube-burner-am-config.yaml
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    envsubst < ci/templates/kube-burner-config.yaml > kube-burner-cs-config.yaml

    start_time=$(date +%s)
    echo "Running the ocm-load-test test"
    build/ocm-load-test --config-file config.yaml --log-file ocm-load-test-log
    cp ocm-load-test-log results/ocm-load-test-log.json

    end_time=$(date +%s)

    echo "Uploading Result files..."
    python3 automation.py upload --dir ~/ocm-api-load/results --server ${SNAPPY_DATA_SERVER_URL} --user ${SNAPPY_DATA_SERVER_USERNAME} --password ${SNAPPY_DATA_SERVER_PASSWORD}

    curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz
    echo "Running kube-burner index to scrap metrics from UHC account manager service from ${start_time} to ${end_time} and push to ES"
    ./kube-burner index -c kube-burner-am-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=ci/templates/metrics_acct_mgmr.yaml --start $start_time --end $end_time
    echo "UHC account manager Metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "Running kube-burner index to scrap metrics from UHC clusters service from ${start_time} to ${end_time} and push to ES"
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    ./kube-burner index -c kube-burner-cs-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=ci/templates/metrics_clusters_service.yaml --start $start_time --end $end_time
    echo "UHC clusters service metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "Removing configuration files"
    rm -f config.yaml kube-burner-am-config.yaml kube-burner-cs-config.yaml

    echo "converting start and end times into milliseconds"
    start_time=`expr $start_time \* 1000`
    end_time=`expr $end_time \* 1000`

    echo "Results URLs"
    echo "Account Manager Dashboard https://grafana.apps.observability.perfscale.devcluster.openshift.com/d/uhc-account-manager/uhc-account-manager?orgId=1&var-uuid=${UUID}&var-datasource=ocm-uhc-acct-mngr&from=$start_time&to=$end_time"
    echo "Clusters Service Dashboard https://grafana.apps.observability.perfscale.devcluster.openshift.com/d/uhc-clusters-service/uhc-clusters-service?orgId=1&var-datasource=ocm-uhc-clusters-service&var-uuid=${UUID}&from=$start_time&to=$end_time"
}

run_ocm_api_load
