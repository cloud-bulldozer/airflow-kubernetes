import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig, constants

import json
import requests

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Task for Indexing Task Status in ElasticSearch
class StatusIndexer():
    def __init__(self, dag, version, release_stream, platform, profile, task):
        self.exec_config = var_loader.get_executor_config_with_cluster_access(version, platform, profile)
        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. 4.6/4.7, major.minor only
        self.release_stream = release_stream # true release stream to follow. Nightlies, CI, etc. 
        self.profile = profile  # e.g. default/ovn


        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="index", version=version, platform=platform, profile=profile)

        # Upstream task this is to index
        self.task = task 
        self.env = {
            "RELEASE_STREAM": self.release_stream,
            "TASK": self.task
        }
        self.git_user = var_loader.get_git_user()
        if self.git_user == 'cloud-bulldozer':
            self.env["ES_INDEX"] = "perf_scale_ci"
        else:
            self.env["ES_INDEX"] = f"{self.git_user}_playground"


    # Create Airflow Task for Indexing Results into ElasticSearch
    def get_index_task(self):
        env = {
            **self.env, 
            **{"ES_SERVER": var_loader.get_elastic_url()},
            **environ
        }

        return BashOperator(
            task_id=f"index_{self.task}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/index.sh ",
            retries=3,
            dag=self.dag,
            trigger_rule="all_done",
            executor_config=self.exec_config,
            env=env
        )

