import json
from util import constants
import requests

def get_latest_release_from_stream(base_url, release_stream):
    url = f"{base_url}/{release_stream}/latest"
    payload = requests.get(url).json()
    latest_accepted_release = payload["name"]
    latest_accepted_release_url = payload["downloadURL"]
    return {
        "openshift_client_location": f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}",
        "openshift_install_binary_url": f"{latest_accepted_release_url}/openshift-install-linux-{latest_accepted_release}"
    }
### Task Variable Generator
### Grabs variables from appropriately placed JSON Files
def build_task_vars(task="install", version="stable", platform="aws", profile="default"):
    default_task_vars = get_default_task_vars(task=task)
    profile_vars = get_profile_task_vars(task=task, version=version, platform=platform, profile=profile)
    return { **default_task_vars, **profile_vars }

### Json File Loads
def get_profile_task_vars(task="install", version="stable", platform="aws", profile="default"):
    file_path = f"{constants.root_dag_dir}/releases/{version}/{platform}/{profile}/{task}.json"
    return get_json(file_path)

def get_default_task_vars(task="install"):
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