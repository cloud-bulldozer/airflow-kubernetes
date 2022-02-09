import sys
from os.path import abspath, dirname
from os import environ

from openshift_nightlies.util import var_loader, kubeconfig, constants, executor
from openshift_nightlies.tasks.install.openshift import AbstractOpenshiftInstaller
from openshift_nightlies.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.tasks.benchmarks import e2e

import requests

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from airflow.models.baseoperator import chain
from airflow.utils.task_group import TaskGroup
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
            c_id = f"{'hosted-'+str(iteration)}"
            yield c_id, self._get_task(operation=c_id)

    # def _add_benchmarks(self, task_group):
    #     with TaskGroup(task_group, prefix_group_id=False, dag=self.dag) as benchmarks:
    #         benchmark_tasks = self._get_e2e_benchmarks(task_group).get_benchmarks()
    #         chain(*benchmark_tasks)
    #     return benchmarks

    # def _get_e2e_benchmarks(self, task_group):
    #     return e2e.E2EBenchmarks(self.dag, self.dag_config, self.release, task_group)

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
            task_id=f"{operation}_cluster",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )

        # self._add_benchmarks(task_group=operation)        
        return task