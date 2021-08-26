# Openshift Nightlies

This Repo defines Airflow DAGs used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code for Tasks as well as release configurations
* `images` - Contains all custom images used in the Airflow DAGs
* `charts` - Helm Charts for the PerfScale Stack (includes Airflow, an EFK Stack for logging, Elastic/Kibana Cluster for results, and an instance of the perf-dashboard)
* `scripts` - Install/Uninstall scripts for the PerfScale Stack


# Installation Methods

> All of these methods (minus the perfscale method which should only be used by perfscale team members) require you to fork this repo into your own user/organization. Please *DO NOT* attempt to install this by simply cloning the [upstream repo](https://github.com/cloud-bulldozer/airflow-kubernetes)

## Tenant

To install Airflow as a Tenant, you can run the following commands from the fork you wish to use as your tenant repo.

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/tenant/create.sh -p $PASSWORD
```

### Uninstalling

To remove the tenant from the cluster, you can run `./scripts/tenant/destroy.sh` from the tenant fork.

---
## Developer Playground

> These instances should be used for development only and not for long-term running of DAGs. These resources may be cleaned up at any time. 

To install Airflow in a developer playground setting (i.e. in our baremetal cluster)

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/playground/build.sh -p $PASSWORD
```

### Cleaning up the Playground
To uninstall the stack, you can run `./scripts/playground/cleanup.sh`.

---

## Installing the PerfScale Stack

> This requires you to have your own openshift cluster. If you wish to install this inside the Performance and Scale Baremetal Cluster (sailplane), please see the [Tenant](#tenant) installation method. We do not actively support this mode of installation for other teams. 

To install the PerfScale stack you can simply run the following on a box that has access to an openshift cluster:

```bash
# all commands are run at the root of your git repo
# install the perfscale stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance behind.
./scripts/perfscale/install.sh -p $PASSWORD
```

### Uninstalling

To uninstall the stack, you can run `./scripts/perfscale/uninstall.sh`.

---