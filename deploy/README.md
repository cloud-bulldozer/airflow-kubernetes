# Leviathan

This repo contains scripts and Argo manifests used to bootstrap an Openshift Cluster with Airflow and hopefully things such as the Benchmark Operator and ElasticSearch.


## Prequisites

An Openshift Cluster deployed via [scale-ci-deploy](https://github.com/openshift-scale/scale-ci-deploy) 

## Installing Airflow 

Run `./install.sh -u $GIT_USER -b $BRANCH -c $CLUSTER_NAME`

Where the GIT_USER is your username, and BRANCH is the branch you want your Airflow DAGs to be pulled from. 
$CLUSTER_NAME is the name you gave your cluster in the scale-ci-deploy playbook.
