#!/bin/bash
_user=$(oc whoami)
GIT_ROOT=$(git rev-parse --show-toplevel)
source $GIT_ROOT/scripts/common.sh
source $GIT_ROOT/scripts/perfscale/check_user_and_repo.sh


kubectl delete application/perf-results -n argocd
kubectl delete application/logging -n argocd
helm delete perfscale -n argocd


while [ $(kubectl get apps -A | wc -l) != "0" ];
do 
    sleep 5
done

kubectl delete namespace fluentd || true
kubectl delete namespace airflow || true
kubectl delete namespace logging || true
kubectl delete namespace elastic-system || true
kubectl delete namespace perf-results || true
kubectl delete namespace argocd || true