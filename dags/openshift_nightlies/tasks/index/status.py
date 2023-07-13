from os import environ


from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig

import json
import requests

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Task for Indexing Task Status in ElasticSearch
class StatusIndexer():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease, task, task_group=""):

        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.task_group = task_group
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release, task_group=self.task_group)

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(release, task="index")

        # Upstream task this is to index
        self.task = task
        self.env = {
            "RELEASE_STREAM": self.release.release_stream,
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
            **{"ES_SERVER": var_loader.get_secret('elasticsearch')},
            **environ
        }
        if self.task != "install":
            command = f'UUID={{{{ ti.xcom_pull("{self.task}") }}}} {constants.root_dag_dir}/scripts/index.sh '
        else:
            command = f'{constants.root_dag_dir}/scripts/index.sh '

        return BashOperator(
            task_id=f"index-{self.task}",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule="all_done",
            executor_config=self.exec_config,
            env=env
        )