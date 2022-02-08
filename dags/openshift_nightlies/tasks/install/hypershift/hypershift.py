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

class HypershiftInstaller(AbstractOpenshiftInstaller):
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):
        super().__init__(dag, config, release)
        self.exec_config = executor.get_executor_config_with_cluster_access(self.dag_config, self.release, executor_image="airflow-managed-services")
        self.hypershift_pull_secret = var_loader.get_secret("hypershift_pull_secret") 

    def get_hosted_install_task(self):
        # hosted_install = []
        config = {
            **self.vars
        }
        # for iteration in range(config['number_of_hosted_cluster']):
        #     hosted_install.append(self._get_task(operation="hosted-"+str(iteration)))
        # return hosted_install

        for iteration in range(config['number_of_hosted_cluster']):
            yield self._get_task(operation="hosted-"+str(iteration))
            
    # def _add_benchmark(self, task):

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="hosted", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        self.env = {
            "PULL_SECRET": self.hypershift_pull_secret,
            **self.env
        }        
        env = {**self.env, **{"HOSTED_NAME": operation}}
        command=f"{constants.root_dag_dir}/scripts/install/hypershift.sh -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}"

        task = BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )

        # self._add_benchmark(task)        
        return task