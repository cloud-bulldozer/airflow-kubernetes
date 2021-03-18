# Openshift Nightlies

This Repo defines Airflow Tasks used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code
* `images` - Contains all custom images used in the Airflow DAGs
* `charts` - Helm Charts for the Airflow Stack (includes Airflow, an EFK Stack for logging, Elastic/Kibana Cluster for results, and an instance of the perf-dashboard)
* `scripts` - Install/Uninstall scripts for the Airflow stack

## Docs

Look at [tasks](./dags/openshift_nightlies/docs/tasks.md) to see more about creating tasks
Look at [variables](./dags/openshift_nightlies/docs/variables.md) to see how variables are handled in these DAGs


## Installing Airflow

To install Airflow you simply need to fork the repo and run the following on a box that has access to an openshift cluster:

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
./scripts/install.sh
```

### Getting Cluster Configuration

To get URLs and login info for the cluster, you can run `./scripts/get_cluster_info.sh` to get the output given at the end of the install.

### Uninstalling

To uninstall the stack, you can run `./scripts/uninstall.sh`.