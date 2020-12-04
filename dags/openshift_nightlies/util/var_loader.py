import json

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"

### Task Variable Generator
### Grabs variables from appropriately placed JSON Files
def build_task_vars(task="install", version="stable", platform="aws", profile="default"):
    default_task_vars = get_default_task_vars(task=task)
    version_vars = get_version_task_vars(task=task, version=version)
    platform_vars = get_platform_task_vars(task=task, version=version, platform=platform)
    profile_vars = get_profile_task_vars(task=task, version=version, platform=platform, profile=profile)
    return { **default_task_vars, **version_vars, **platform_vars, **profile_vars }

### Json File Loads

def get_profile_task_vars(task="install", version="stable", platform="aws", profile="default"):
    file_path = f"{root_dag_dir}/tasks/{task}/profiles/{version}/{platform}/{profile}.json"
    return get_json(file_path)

def get_platform_task_vars(task="install", version="stable", platform="aws"):
    file_path = f"{root_dag_dir}/tasks/{task}/profiles/{version}/{platform}/default.json"
    return get_json(file_path)

def get_version_task_vars(task="install", version="stable"):
    file_path = f"{root_dag_dir}/tasks/{task}/profiles/{version}/defaults.json"
    return get_json(file_path)

def get_default_task_vars(task="install"):
    file_path = f"{root_dag_dir}/tasks/{task}/profiles/default.json"
    return get_json(file_path)


def get_json(file_path):
    try: 
        with open(file_path) as json_file:
            return json.load(json_file)
    except IOError as e: 
        return {}