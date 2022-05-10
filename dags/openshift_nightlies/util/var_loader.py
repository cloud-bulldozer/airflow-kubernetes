import json
from os import environ
from openshift_nightlies.util import constants
from openshift_nightlies.models.release import OpenshiftRelease

import requests
from airflow.models import Variable
from kubernetes.client import models as k8s


# Used to get the git user for the repo the dags live in. 
def get_git_user():
    git_repo = environ['GIT_REPO']
    git_path = git_repo.split("https://github.com/")[1]
    git_user = git_path.split('/')[0]
    return git_user.lower()


def get_secret(name, deserialize_json=False, required=True):
    if required:
        return Variable.get(name, deserialize_json=deserialize_json)
    else:
        try:
            return Variable.get(name, deserialize_json=deserialize_json)
        except KeyError:
            return {}


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
    elif release.platform == 'hypershift' and "hosted" in task:
        file_path = f"{config_dir}/benchmarks/{release.config['benchmarks']}"
        return get_json(file_path)
    elif task in release.config:
        file_path = f"{config_dir}/{task}/{release.config[task]}"
        return get_json(file_path)
    else:
        return {}

def get_default_task_vars(release: OpenshiftRelease, task="install", task_dir=f"{constants.root_dag_dir}/tasks"):
    if task == "install":
        if release.platform == "aws" or release.platform == "azure" or release.platform == "gcp" or release.platform == "alibaba":
            file_path = f"{task_dir}/{task}/cloud/defaults.json"
        else:
            file_path = f"{task_dir}/{task}/{release.platform}/defaults.json"
    else:
        file_path = f"{task_dir}/{task}/defaults.json"
    return get_json(file_path)


def get_json(file_path):
    try: 
        with open(file_path) as json_file:
            return json.load(json_file)
    except IOError as e:
        return {}
    except Exception as e:
        raise Exception(f"json file {file_path} failed to parse") 
