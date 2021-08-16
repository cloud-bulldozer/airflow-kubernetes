#!/bin/bash
_unauthorized_user="
ERROR: You are trying to either install or delete the core infra of the perfscale cluster, yet you are only assigned the role $_user. You must be a cluster admin to do this. 
If you trying to leverage Airflow to run performance tests or developing against this repo, please use the tenant or playground installation methods.
https://github.com/cloud-bulldozer/airflow-kubernetes/blob/master/README.md
"

_wrong_repo="
ERROR: You are trying to either install or delete the core infra of the perfscale cluster from a fork of this repo. This is not allowed.
You can only run this script from the master branch of https://github.com/cloud-bulldozer/airflow-kubernetes.
If you trying to leverage Airflow to run performance tests or developing against this repo, please use the tenant or playground installation methods.
https://github.com/cloud-bulldozer/airflow-kubernetes/blob/master/README.md
"

if [ "$_user" != "system:admin" ]; then
    echo "$_unauthorized_user"
    exit 1
elif [ "$_remote_origin_url" != "https://github.com/cloud-bulldozer/airflow-kubernetes.git" ] || [ "$_branch" != "master" ]; then 
    echo "$_wrong_repo"
    exit 1
fi