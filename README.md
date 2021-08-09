# Openshift Nightlies

This Repo defines Airflow Tasks used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code
* `images` - Contains all custom images used in the Airflow DAGs
* `charts` - Helm Charts for the Airflow Stack (includes Airflow, an EFK Stack for logging, Elastic/Kibana Cluster for results, and an instance of the perf-dashboard)
* `scripts` - Install/Uninstall scripts for the Airflow stack

## Installing Airflow [Standalone]

> Note: This requires you to have your own openshift cluster. If you wish to install this inside the Performance and Scale Baremetal Cluster (sailplane), please see the [Developer Playground](#installing-airflow-developer-playground)

To install Airflow you simply need to fork the repo and run the following on a box that has access to an openshift cluster:

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance behind.
./scripts/install.sh -p $PASSWORD
```

### Getting Cluster Configuration

To get URLs and login info for the cluster, you can run `./scripts/get_cluster_info.sh` to get the output given at the end of the install.

### Uninstalling

To uninstall the stack, you can run `./scripts/uninstall.sh`.




## Installing Airflow (Developer Playground)

> Note: This currently only works if you clone the repo using https!

To install Airflow in a developer playground setting (i.e. in our baremetal cluster)

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/playground/build.sh -p $PASSWORD
```

## Cleaning up the Playground
To uninstall the stack, you can run `./scripts/playground/cleanup.sh`.