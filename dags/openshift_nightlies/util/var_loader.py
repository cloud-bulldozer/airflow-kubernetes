import json
from util import constants
import requests
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter

def get_latest_release_from_stream(base_url, release_stream):
    session = requests.Session()
    retries = Retry(
        total=5,
        backoff_factor=1,
        status_forcelist=[ 404, 500, 502, 503, 504 ]
    )

    url = f"{base_url}/{release_stream}/latest"
    payload = requests.get(url).json()

    latest_accepted_release = payload["name"]
    latest_accepted_release_url = payload["downloadURL"]

    # hit the release url to ensure the release app has started serving the artifacts
    session.mount('http://', HTTPAdapter(max_retries=retries))
    session.get(latest_accepted_release_url)

    # This should retry a total a 5 times until the request returns 200, indicating the binaries have been extracted. 
    session.get(f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}.tar.gz")
    return {
        "openshift_client_location": f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}.tar.gz",
        "openshift_install_binary_url": f"{latest_accepted_release_url}/openshift-install-linux-{latest_accepted_release}.tar.gz"
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