import sys
from os.path import abspath, dirname
from os import environ

from openshift_nightlies.util import var_loader, kubeconfig, constants, executor
from openshift_nightlies.tasks.install.openshift import AbstractOpenshiftInstaller
from openshift_nightlies.tasks.utils import rosa_post_install
from common.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease

import requests
import uuid

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

import json

# Defines Tasks for installation of Openshift Clusters

class RosaInstaller(AbstractOpenshiftInstaller):
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):
        super().__init__(dag, config, release)
        self.exec_config = executor.get_default_executor_config(self.dag_config, executor_image="airflow-managed-services")
        self.rosa_postinstall_setup = rosa_post_install.Diagnosis(dag, config, release)

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", id="", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        task_prefix=f"{id}-"
        self.env = {
            "ES_SERVER": var_loader.get_secret('elasticsearch'),
            "ES_INDEX": "ripsaw-kube-burner",
            "THANOS_RECEIVER_URL": var_loader.get_secret("thanos_receiver_url"),
            "PROM_URL": var_loader.get_secret("thanos_querier_url"),       
            **self.env
        }
        env = {**self.env}
        command=f"{constants.root_dag_dir}/scripts/install/rosa.sh -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}"

        return BashOperator(
            task_id=f"{task_prefix if id != '' else ''}{operation}",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )
