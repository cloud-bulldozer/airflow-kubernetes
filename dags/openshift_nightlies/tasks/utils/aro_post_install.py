import json
from datetime import timedelta
from os import environ

from airflow.models import DAG, Variable
from airflow.operators.bash import BashOperator
from airflow.operators.subdag import SubDagOperator
from airflow.utils.task_group import TaskGroup
from common.models.dag_config import DagConfig
from kubernetes.client import models as k8s
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.util import constants, executor, var_loader


class Diagnosis():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):

        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.release_name = release.get_release_name(delimiter="-")

        self.aws_creds = var_loader.get_secret(
            "aws_creds", deserialize_json=True)

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

        self.exec_config = executor.get_executor_config_with_cluster_access(
            self.config, self.release, executor_image="airflow-managed-services")

    def _get_rosa_postinstallation(self, operation="postinstall", trigger_rule="all_success"):
        return BashOperator(
            task_id=f"{operation}_rosa",
            depends_on_past=False,
            bash_command=f"python {constants.root_dag_dir}/scripts/utils/aro_post_install.py --jsonfile /tmp/{self.release_name}-postinstall-task.json --kubeconfig /home/airflow/auth/config",
            retries=3,
            dag=self.dag,
            executor_config=self.exec_config,
            trigger_rule=trigger_rule
        )
