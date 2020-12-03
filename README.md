# Openshift Nightlies

This Repo defines Airflow Tasks used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code
* `images` - Contains all custom images used in the Airflow DAGs
* `airflow` - Helm Chart used to deploy Airflow into a Kubernetes/Openshift Cluster

## Docs

Look at [tasks](./docs/tasks.md) to see more about creating tasks
Look at [variables](./docs/variables.md) to see how variables are handled in these DAGs


## Installing Airflow

Refer to the [Leviathan Repo](https://github.com/whitleykeith/leviathan)