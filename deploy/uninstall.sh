#!/bin/bash
set -x 


helm delete airflow -n airflow
kubectl delete namespace airflow
kubectl delete application airflow -n argocd
