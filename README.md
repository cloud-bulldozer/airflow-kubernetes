# Openshift Nightlies

This Repo defines Airflow DAGs used in running our nightly performance builds for stable and future releases of Openshift.


## Overview

* `dags/openshift_nightlies` - Contains all Airflow code for Tasks as well as release configurations
* `images` - Contains all custom images used in the Airflow DAGs
* `charts` - Helm Charts for the PerfScale Stack (includes Airflow, an EFK Stack for logging, Elastic/Kibana Cluster for results, and an instance of the perf-dashboard)
* `scripts` - Install/Uninstall scripts for the PerfScale Stack


# Installation Methods

> All of these methods require you to fork this repo into your own user/organization. Please *DO NOT* attempt to install this by simply cloning the [upstream repo](https://github.com/cloud-bulldozer/airflow-kubernetes)

## Developer Playground

> These instances should be used for development only or ad-hoc performance runs and not for long-term running of DAGs. These resources may be cleaned up at any time. 

To install Airflow in a developer playground setting (i.e. in our baremetal cluster)

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/playground/build.sh -p $PASSWORD
```
### Ad-hoc Performance Tests

Playgrounds are the recommend method if you want to run some ad-hoc performance tests against Openshift Clusters. In your own playground you can easily change install/benchmark configs by making changes to the relevant json files under the `config` directory. For instance, to pin a DAG to a specific version, you can update one of the install config files and add these variables (note: this only works for aws/azure/gcp/cloud at the moment)

```json
{
    "openshift_client_location": "foo",
    "openshift_install_binary_url": "bar"
}

```

Once pushed to your fork this change would apply to all variants using that install config. This works for any of the install configuration fields. 

### Cleaning up the Playground
To uninstall the stack, you can run `./scripts/playground/cleanup.sh`.



---

## Tenant

The tenant method is almost identical to the playground except it doesn't use your branch name in the install of airflow. This means you can only have 1 running tenant installation per git user. This is more useful for teams that wish to have their own long running airflow not tied to the production git repo. To install Airflow as a Tenant, you can run the following commands from the fork you wish to use as your tenant repo.

```bash
# all commands are run at the root of your git repo
# install the airflow stack and have it point to your fork of the dag code.
# $PASSWORD refers to the password you would like to secure your airflow instance with.
./scripts/tenant/create.sh -p $PASSWORD
```

### Uninstalling

To remove the tenant from the cluster, you can run `./scripts/tenant/destroy.sh` from the tenant fork.

---
