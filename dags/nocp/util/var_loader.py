import json
from os import environ
from nocp.util import constants
from common.util import var_loader

import requests
from airflow.models import Variable
from kubernetes.client import models as k8s


get_json=var_loader.get_json
get_git_user=var_loader.get_git_user
get_secret=var_loader.get_secret

def build_nocp_task_vars(app, task="benchmarks", config_dir=f"{constants.root_dag_dir}/config"):
    return get_json(f"{config_dir}/{task}/{app}.json")
