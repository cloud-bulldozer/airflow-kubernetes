import json
from os import environ

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


def get_json(file_path):
    try: 
        with open(file_path) as json_file:
            return json.load(json_file)
    except IOError as e:
        return {}
    except Exception as e:
        raise Exception(f"json file {file_path} failed to parse") 
