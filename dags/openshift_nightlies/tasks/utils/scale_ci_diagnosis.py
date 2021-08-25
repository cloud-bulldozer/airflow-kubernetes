from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig

import json
from datetime import timedelta
from airflow.operators.bash import BashOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s




class Diagnosis():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):

        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release)
        self.snappy_creds = var_loader.get_secret("snappy_creds", deserialize_json=True)

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            release=self.release, task="utils")
        self.git_name=self._git_name()
        self.env = {
            "SNAPPY_DATA_SERVER_URL": self.snappy_creds['server'],
            "SNAPPY_DATA_SERVER_USERNAME": self.snappy_creds['username'],
            "SNAPPY_DATA_SERVER_PASSWORD": self.snappy_creds['password'],
            "SNAPPY_USER_FOLDER": self.git_name

        }


    def _git_name(self):
        git_username = var_loader.get_git_user()
        if git_username == 'cloud-bulldozer':
            return f"perf-ci"
        else: 
            return f"{git_username}"

    def get_utils(self):
        utils = self._get_utils(self.vars["utils"])
        return utils

    def _get_utils(self,utils):
        for index, util in enumerate(utils):
            utils[index] = self._get_util(util)
        return utils 

    def _get_util(self, util):
        env = {**self.env, **util.get('env', {}), **{"ES_SERVER": var_loader.get_secret('elasticsearch')}, **{"KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        return BashOperator(
            task_id=f"{util['name']}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/utils/run_scale_ci_diagnosis.sh -w {util['workload']} -c {util['command']} ",
            retries=3,
            dag=self.dag,
            env=env,
            executor_config=self.exec_config
        )


