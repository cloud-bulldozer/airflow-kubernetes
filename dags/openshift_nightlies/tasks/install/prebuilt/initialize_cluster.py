import abc
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig
from os import environ
import json
import requests
from abc import ABC, abstractmethod

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

from openshift_nightlies.tasks.install.openshift import AbstractOpenshiftInstaller

class InitializePrebuiltCluster():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):

        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.dag_config = config
        self.release_name = release.get_release_name(delimiter="-")
        self.cluster_name = release._generate_cluster_name()

        # Airflow Variables
        self.ansible_orchestrator = var_loader.get_secret(
            "ansible_orchestrator", deserialize_json=True)

        self.exec_config = executor.get_default_executor_config(self.dag_config)

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        self.config = {
            **self.ansible_orchestrator,
            **{ "es_server": var_loader.get_secret('elasticsearch'),
                "thanos_receiver_url": var_loader.get_secret('thanos_receiver_url'),
                "loki_receiver_url": var_loader.get_secret('loki_receiver_url') }
        }

        self.env = {
            "OPENSHIFT_CLUSTER_NAME": self.cluster_name,
            "KUBECONFIG_NAME": f"{self.release_name}-kubeconfig",
            "KUBEADMIN_NAME": f"{self.release_name}-kubeadmin",
            **self._insert_kube_env()
        }

    def initialize_cluster_task(self):
        return BashOperator(
            task_id=f"initialize_cluster",
            depends_on_past=False,
            bash_command=f"{ constants.root_dag_dir }/scripts/install/prebuilt.sh -u {{{{ params.KUBEUSER }}}} -p {{{{ params.KUBEPASSWORD }}}} -w {{{{ params.KUBEURL }}}}",
            retries=1,
            dag=self.dag,
            executor_config=self.exec_config,
            env=self.env
        )


    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}
