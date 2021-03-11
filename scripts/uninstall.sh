#!/bin/bash

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