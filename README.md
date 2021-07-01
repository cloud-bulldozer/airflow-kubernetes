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
# $PASSWORD refers to the password you would like to secure your airflow instance behind.
./scripts/install.sh -p $PASSWORD
```

### Getting Cluster Configuration

To get URLs and login info for the cluster, you can run `./scripts/get_cluster_info.sh` to get the output given at the end of the install.

### Uninstalling

To uninstall the stack, you can run `./scripts/uninstall.sh`.




## Installing Airflow (Developer Playground)

To install Airflow in a developer playground setting (i.e. in our baremetal cluster)

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/playground/build.sh -p $PASSWORD
```

## Cleaning up the Playground
To uninstall the stack, you can run `./scripts/playground/cleanup.sh`.


## CodeStyling and Linting
We use [pre-commit](https://pre-commit.com) framework to maintain the code linting and python code styling.
The CI would run the pre-commit check on each pull request.
We encourage our contributors to follow the same pattern, while contributing to the code.

The pre-commit configuration file is present in the repository `.pre-commit-config.yaml`
It contains the different code styling and linting guide which we use for the application.

Following command can be used to run the pre-commit:
`pre-commit run --all-files`

If pre-commit is not installed in your system, it can be install with : `pip install pre-commit`
