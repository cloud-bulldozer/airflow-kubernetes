#!/bin/bash
set -a
usage() { echo "Usage: $0 [-p <string> (airflow password)]" 1>&2; exit 1; }
GIT_ROOT=$(git rev-parse --show-toplevel)
source $GIT_ROOT/scripts/common.sh
_airflow_namespace=$_remote_user-$_branch-airflow



envsubst < $GIT_ROOT/scripts/playground/templates/airflow.yaml | kubectl delete -f -
oc delete project/$_airflow_namespace || true
