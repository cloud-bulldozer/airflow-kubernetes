import json

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"

### Json File Loads

def get_common_vars():
    file_path = f"{root_dag_dir}/vars/common.json"
    return get_json(file_path)
    

def get_common_install_vars(version="stable"):
    file_path = f"{root_dag_dir}/vars/{version}/install_cluster/common.json"
    return get_json(file_path)

def get_profile_install_vars(version="stable", platform="aws", profile="default"):
    file_path = f"{root_dag_dir}/vars/{version}/install_cluster/{platform}/{profile}.json"
    return get_json(file_path)
    pass


def get_json(file_path):
    with open(file_path) as json_file:
        return json.load(json_file)