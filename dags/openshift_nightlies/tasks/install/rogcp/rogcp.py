import sys
from os.path import abspath, dirname
from os import environ

from openshift_nightlies.util import var_loader, kubeconfig, constants, executor
from openshift_nightlies.tasks.install.openshift import AbstractOpenshiftInstaller
from openshift_nightlies.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease

import requests

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

import json

# Defines Tasks for installation of Openshift Clusters

class RoGCPInstaller(AbstractOpenshiftInstaller):
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):
        super().__init__(dag, config, release)
        self.exec_config = executor.get_default_executor_config(self.dag_config, executor_image="airflow-managed-services")

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        command=f"{constants.root_dag_dir}/scripts/install/ocm_gcp.sh -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}"
        env={ **self.env , "InstallUUID": '{{ ti.xcom_pull(task_ids="install")}}'}
        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )
