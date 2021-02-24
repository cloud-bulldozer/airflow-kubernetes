#!/bin/bash

set -exo pipefail


while getopts d:e: flag
do
    case "${flag}" in
        d) dag_id=${OPTARG};;
        e) execution_date=${OPTARG};;
    esac
done

setup(){

}

4.6_aws_default
	2021-02-22T19:44:45.631939+00:00


# Defaults
if [[ -z $ES_SERVER ]]; then
  echo "Elastic server is not defined, please check"
  help
  exit 1
fi
if [[ -z $ES_USER ]]; then
  export ES_USER=""
else
  export ES_USER="--user ${ES_USER}"
fi
if [[ -z $ES_INDEX ]]; then
  export ES_INDEX=perf_scale_ci
fi
if [[ -z $dag_id ]] || [[ -z $execution_date ]]; then
    echo "Dag ID or execution date is missing, exiting"
    exit 1