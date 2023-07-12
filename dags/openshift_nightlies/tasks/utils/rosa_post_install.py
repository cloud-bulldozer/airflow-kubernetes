from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig

import json
from datetime import timedelta
from airflow.operators.bash import BashOperator
from airflow.operators.subdag import SubDagOperator
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
        self.release_name = release.get_release_name(delimiter="-")

        self.aws_creds = var_loader.get_secret("aws_creds", deserialize_json=True)

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            release=self.release, task="install")

        self.all_vars = {
            **self.vars,
            **self.aws_creds,
        }

        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.release_name}-postinstall-task.json", 'w') as json_file:
            json.dump(self.all_vars, json_file, sort_keys=True, indent=4)

        super().__init__()

    def _get_rosa_postinstallation(self, operation="postinstall", id="", trigger_rule="all_success"):
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release, executor_image="airflow-managed-services", task_group=id)
        task_prefix=f"{id}-"
        return BashOperator(
            task_id=f"{task_prefix if id != '' else ''}{operation}-rosa",
            depends_on_past=False,
            bash_command=f"python {constants.root_dag_dir}/scripts/utils/rosa_post_install.py --jsonfile /tmp/{self.release_name}-postinstall-task.json --kubeconfig /home/airflow/auth/config",
            retries=3,
            dag=self.dag,
            executor_config=self.exec_config,
            trigger_rule=trigger_rule
        )
