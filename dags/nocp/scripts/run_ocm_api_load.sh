#!/bin/bash

# declare tests with rate and duration. Duration will be in minutes
# create_cluster, create-services, get-services and patch-services skipped till they get fixed and stabilized
export tests="
self-access-token 5/s 30 \n
list-subscriptions 5/s 30 \n
access-review 100/s 30 \n
register-new-cluster 10/s 30 \n
register-existing-cluster 100/s 30 \n
list-clusters 20/s 30 \n
get-current-account 10/s 10 \n
quota-cost 10/s 30 \n
resource-review 5/s 30 \n
cluster-authorizations 10/s 15 \n
self-terms-review 30/s 10 \n
certificates 15/s 10"

create_aws_key(){
    # Delete aws keys if more than 1 key exists
    arr=(`aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId'`)
    arraylength=${#arr[@]}
    if [[ $arraylength -ge 1 ]]; then
        unset arr[$arraylength-1]
    fi
    for i in ${!arr[@]}
    do
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id ${arr[i]}
    done

    echo "Creating aws key with admin user for OCM testing"
    admin_key=$(aws iam create-access-key --user-name OsdCcsAdmin --output json)
    export AWS_OSDCCADMIN_KEY=$(echo $admin_key | jq -r '.AccessKey.AccessKeyId')
    export AWS_OSDCCADMIN_SECRET=$(echo $admin_key | jq -r '.AccessKey.SecretAccessKey')
    sleep 60
}


run_ocm_api_load(){
    BASEDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    echo "Base directory $BASEDIR"

    # export environment variables shared by airflow (avoid overriding local env vars)
    env > $BASEDIR/local_env.txt
    while IFS="=" read -r key value; do
        if ! grep -q "$key=" $BASEDIR/local_env.txt; then
                export $key=$value
        fi
    done < $BASEDIR/environment.txt

    echo "# Benchmark UUID: ${UUID}"

    echo " Clone and build the binary"
    git clone https://github.com/cloud-bulldozer/ocm-api-load $BASEDIR/ocm-api-load
    export TESTDIR=$BASEDIR/ocm-api-load
    echo "Test directory $TESTDIR"
    cd $TESTDIR
    go mod download
    make

    create_aws_key

    # Run each test individually
    start_time=$(date +%s)
    echo -e $tests | while read tname trate tduration; do

        # As each test runs for a longer duration, aws OsdCcsAdmin key migt have been deleted if rosa cluster is created in parallel
        aws_osdccadmin_keys=`aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId'`
        if [[ "$aws_osdccadmin_keys" != *"$AWS_OSDCCADMIN_KEY"* ]]; then
            echo "create AWS OsdCcsAdmin key as it got deleted..."
            create_aws_key
        fi

	# Timeout runs ocm-load-test for the specified duration even if airflow killed this script (when user wants to stop benchmark execution). This helps in ocm-load-test to cleanup resources it created. 10 minutes extra timeout is set so that test can prepare results after running for the given duration.
	# kill-after option needs sudo permissions
        timeout --kill-after=60s --preserve-status $(((tduration + 10) * 60)) $TESTDIR/build/ocm-load-test --aws-region $AWS_DEFAULT_REGION --aws-account-id $AWS_ACCOUNT_ID --aws-access-key $AWS_OSDCCADMIN_KEY --aws-access-secret $AWS_OSDCCADMIN_SECRET --cooldown $COOLDOWN --duration $tduration --elastic-index ocm-request-test --elastic-insecure-skip-verify=true --elastic-server $ES_SERVER --gateway-url $GATEWAY_URL --ocm-token $OCM_TOKEN --ocm-token-url $OCM_TOKEN_URL --output-path $TESTDIR/results --rate $trate --test-id $UUID --test-names $tname
	sleep $COOLDOWN
    done
    benchmark_rv=$?
    end_time=$(date +%s)

    echo "Uploading Result files..."
    python3 $TESTDIR/automation.py upload --dir $TESTDIR/results --server ${SNAPPY_DATA_SERVER_URL} --user ${SNAPPY_DATA_SERVER_USERNAME} --password ${SNAPPY_DATA_SERVER_PASSWORD}

    # scraping metrics
    export KUBE_ES_INDEX=ocm-uhc-acct-mngr
    envsubst < $TESTDIR/ci/templates/kube-burner-config.yaml > $TESTDIR/kube-burner-am-config.yaml
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    envsubst < $TESTDIR/ci/templates/kube-burner-config.yaml > $TESTDIR/kube-burner-cs-config.yaml
    curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz --directory=$TESTDIR/
    echo "Running kube-burner index to scrap metrics from UHC account manager service from ${start_time} to ${end_time} and push to ES"
    $TESTDIR/kube-burner index -c $TESTDIR/kube-burner-am-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=$TESTDIR/ci/templates/metrics_acct_mgmr.yaml --start $start_time --end $end_time
    echo "UHC account manager Metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "Running kube-burner index to scrap metrics from UHC clusters service from ${start_time} to ${end_time} and push to ES"
    export KUBE_ES_INDEX=ocm-uhc-clusters-service
    $TESTDIR/kube-burner index -c $TESTDIR/kube-burner-cs-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=$TESTDIR/ci/templates/metrics_clusters_service.yaml --start $start_time --end $end_time
    echo "UHC clusters service metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

    echo "converting start and end times into milliseconds for creating Result URLs"
    start_time=`expr $start_time \* 1000`
    end_time=`expr $end_time \* 1000`

    echo "Results URLs"
    echo "Account Manager Dashboard $GRAFANA_URL/d/uhc-account-manager/uhc-account-manager?orgId=1&var-uuid=${UUID}&var-datasource=ocm-uhc-acct-mngr&from=$start_time&to=$end_time"
    echo "Clusters Service Dashboard $GRAFANA_URL/d/uhc-clusters-service/uhc-clusters-service?orgId=1&var-datasource=ocm-uhc-clusters-service&var-uuid=${UUID}&from=$start_time&to=$end_time"

    # echo $UUID at the end is needed to pass UUID to cleanup task
    echo $UUID
    exit $benchmark_rv
}

run_ocm_api_load
