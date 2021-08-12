import json
from openshift_nightlies.util import constants, executor
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

def get_secret(name, deserialize_json=False):
    overrides = get_overrides()
    if name in overrides:
        return overrides[name]
    return Variable.get(name, deserialize_json=deserialize_json)

def get_overrides():
    try:
        return Variable.get("overrides", deserialize_json=True)
    except KeyError as e: 
        print(e)
    return {}
    


### Task Variable Generator
### Grabs variables from appropriately placed JSON Files
def build_task_vars(release: OpenshiftRelease, task="install"):
    default_task_vars = get_default_task_vars(release=release, task=task)
    profile_vars = get_profile_task_vars(release=release, task=task)
    return { **default_task_vars, **profile_vars }

### Json File Loads
def get_profile_task_vars(release: OpenshiftRelease, task="install"):
    file_path = f"{constants.root_dag_dir}/releases/{release.version}/{release.platform}/{release.profile}/{task}.json"
    return get_json(file_path)

def get_default_task_vars(release: OpenshiftRelease, task="install"):
    if task == "install":
        if release.platform == "aws" or release.platform == "azure" or release.platform == "gcp":
            file_path = f"{constants.root_dag_dir}/tasks/{task}/cloud/defaults.json"
        else:
            file_path = f"{constants.root_dag_dir}/tasks/{task}/{release.platform}/defaults.json"
    else:
        file_path = f"{constants.root_dag_dir}/tasks/{task}/defaults.json"
    return get_json(file_path)


def get_json(file_path):
    try: 
        with open(file_path) as json_file:
            return json.load(json_file)
    except IOError as e:
        return {}
    except Exception as e:
        raise Exception(f"json file {file_path} failed to parse") 