import json
from os import environ
from common.util import var_loader
from openshift_nightlies.util import constants
from openshift_nightlies.models.release import OpenshiftRelease

import requests
from airflow.models import Variable
from kubernetes.client import models as k8s


get_json=var_loader.get_json
get_git_user=var_loader.get_git_user
get_secret=var_loader.get_secret

### Task Variable Generator
### Grabs variables from appropriately placed JSON Files
def build_task_vars(release: OpenshiftRelease, task="install", config_dir=f"{constants.root_dag_dir}/config", task_dir=f"{constants.root_dag_dir}/tasks"):
    default_task_vars = get_default_task_vars(release=release, task=task, task_dir=task_dir)
    config_vars = get_config_vars(release=release, task=task, config_dir=config_dir)
    return { **default_task_vars, **config_vars }

def get_config_vars(release: OpenshiftRelease, task="install", config_dir=f"{constants.root_dag_dir}/config"):
    # baremetal has multiple benchmark groups so it needs to be handled separately
    if release.platform == 'baremetal' and "bench" in task: 
        file_path = f"{config_dir}/{release.config['benchmarks']}/{task}.json"
        return get_json(file_path)
    elif ( release.platform == 'hypershift' or release.platform == 'rosa'or release.platform == 'rosahcp' ) and "hcp" in task:
        file_path = f"{config_dir}/benchmarks/{release.config['benchmarks']}"
        return get_json(file_path)
    elif task in release.config:
        file_path = f"{config_dir}/{task}/{release.config[task]}"
        return get_json(file_path)
    else:
        return {}

def get_default_task_vars(release: OpenshiftRelease, task="install", task_dir=f"{constants.root_dag_dir}/tasks"):
    if task == "install":
        if release.platform in ( "aws" , "aws-arm" , "azure" , "gcp" , "alibaba" ):
            file_path = f"{task_dir}/{task}/cloud/defaults.json"
        else:
            file_path = f"{task_dir}/{task}/{release.platform}/defaults.json"
    else:
        file_path = f"{task_dir}/{task}/defaults.json"
    return get_json(file_path)
