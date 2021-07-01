import json
import sys
from os.path import abspath, dirname
from os import environ
sys.path.insert(0, dirname(abspath(dirname(__file__))))
from util import constants, kubeconfig
import requests
from airflow.models import Variable
from kubernetes.client import models as k8s


# Used to get the git user for the repo the dags live in. 
def get_git_user():
    git_repo = environ['GIT_REPO']
    git_path = git_repo.split("https://github.com/")[1]
    git_user = git_path.split('/')[0]
    return git_user.lower()

def get_latest_release_from_stream(base_url, release_stream):
    url = f"{base_url}/{release_stream}/latest"
    payload = requests.get(url).json()
    latest_accepted_release = payload["name"]
    latest_accepted_release_url = payload["downloadURL"]
    return {
        "openshift_client_location": f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}.tar.gz",
        "openshift_install_binary_url": f"{latest_accepted_release_url}/openshift-install-linux-{latest_accepted_release}.tar.gz"
    }

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

def get_executor_config_with_cluster_access(version, platform, profile):
    return {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.1.0",
                            image_pull_policy="Always",
                            env=[
                                kubeconfig.get_kubeadmin_password(
                        version, platform, profile)
                            ],
                            volume_mounts=[
                                kubeconfig.get_kubeconfig_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_kubeconfig_volume(
                        version, platform, profile)]
                )
            )
        }


### Task Variable Generator
### Grabs variables from appropriately placed JSON Files
def build_task_vars(task="install", version="stable", platform="aws", profile="default"):
    default_task_vars = get_default_task_vars(task=task, platform=platform)
    profile_vars = get_profile_task_vars(task=task, version=version, platform=platform, profile=profile)
    return { **default_task_vars, **profile_vars }

### Json File Loads
def get_profile_task_vars(task="install", version="stable", platform="aws", profile="default"):
    file_path = f"{constants.root_dag_dir}/releases/{version}/{platform}/{profile}/{task}.json"
    return get_json(file_path)

def get_default_task_vars(task="install", platform="aws"):
    if task == "install":
        if platform == "aws" or platform == "azure" or platform == "gcp":
            file_path = f"{constants.root_dag_dir}/tasks/{task}/cloud/defaults.json"
        else:
            file_path = f"{constants.root_dag_dir}/tasks/{task}/{platform}/defaults.json"
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