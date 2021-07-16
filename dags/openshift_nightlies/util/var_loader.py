import json
import sys
from os.path import abspath, dirname
from os import environ
sys.path.insert(0, dirname(abspath(dirname(__file__))))
from util import constants, kubeconfig
from models.release import OpenshiftRelease
import requests
from airflow.models import Variable
from kubernetes.client import models as k8s


# Used to get the git user for the repo the dags live in. 
def get_git_user():
    git_repo = environ['GIT_REPO']
    git_path = git_repo.split("https://github.com/")[1]
    git_user = git_path.split('/')[0]
    return git_user.lower()

def get_elastic_url():
    elasticsearch_config = Variable.get("elasticsearch_config", deserialize_json=True)
    if 'username' in elasticsearch_config and 'password' in elasticsearch_config:
        return f"http://{elasticsearch_config['username']}:{elasticsearch_config['password']}@{elasticsearch_config['url']}"
    else:
        return elasticsearch_config['url']

def get_default_executor_config():
    return {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.1.0",
                            image_pull_policy="Always",
                            volume_mounts=[
                                kubeconfig.get_empty_dir_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_empty_dir_volume_mount()]
                )
            )
        }

def get_executor_config_with_cluster_access(release: OpenshiftRelease):
    return {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.1.0",
                            image_pull_policy="Always",
                            env=[
                                kubeconfig.get_kubeadmin_password(release)
                            ],
                            volume_mounts=[
                                kubeconfig.get_kubeconfig_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_kubeconfig_volume(release)]
                )
            )
        }


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

def get_manifest_vars():
    file_path = f"{constants.root_dag_dir}/manifest.json"
    return get_json(file_path)




def get_json(file_path):
    try: 
        with open(file_path) as json_file:
            return json.load(json_file)
    except IOError as e:
        return {}
    except Exception as e:
        raise Exception(f"json file {file_path} failed to parse") 