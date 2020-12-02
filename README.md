# Openshift Nightlies

This Repo defines Airflow Tasks used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code
* `images` - Contains all custom images used in the Airflow DAGs
* `airflow` - Helm Chart used to deploy Airflow into a Kubernetes/Openshift Cluster

