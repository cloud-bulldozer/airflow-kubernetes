import abc
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig
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

        # Specific Task Configuration
        #self.vars = var_loader.build_task_vars(release, task="install")

        # Airflow Variables
        self.ansible_orchestrator = var_loader.get_secret(
            "ansible_orchestrator", deserialize_json=True)

        self.install_secrets = var_loader.get_secret(
            f"openshift_install_config", deserialize_json=True)
        self.aws_creds = var_loader.get_secret("aws_creds", deserialize_json=True)
        self.gcp_creds = var_loader.get_secret("gcp_creds", deserialize_json=True)
        self.azure_creds = var_loader.get_secret("azure_creds", deserialize_json=True)
        self.ocp_pull_secret = var_loader.get_secret("osp_ocp_pull_creds")
        self.openstack_creds = var_loader.get_secret("openstack_creds", deserialize_json=True)
        self.rosa_creds = var_loader.get_secret("rosa_creds", deserialize_json=True)
        self.rhacs_creds = var_loader.get_secret("rhacs_creds", deserialize_json=True)
        self.rogcp_creds = var_loader.get_secret("rogcp_creds")
        #self.release_stream_base_url = var_loader.get_secret("release_stream_base_url")
        self.exec_config = executor.get_default_executor_config(self.dag_config)

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        self.config = {
            #**self.vars,
            **self.ansible_orchestrator,
            **self.install_secrets,
            **self.aws_creds,
            **self.gcp_creds,
            **self.azure_creds,
            **self.openstack_creds,
            **self.rosa_creds,
            **self.rhacs_creds,
            #**self.release.get_latest_release(self.release_stream_base_url),
            **{ "es_server": var_loader.get_secret('elasticsearch'),
                "thanos_receiver_url": var_loader.get_secret('thanos_receiver_url'),
                "loki_receiver_url": var_loader.get_secret('loki_receiver_url') }
        }

        #self.config['openshift_cluster_name'] = self.cluster_name
        #self.config['dynamic_deploy_path'] = f"{self.config['openshift_cluster_name']}"
        #self.config['kubeconfig_path'] = f"/root/{self.config['dynamic_deploy_path']}/auth/kubeconfig"
        self.env = {
            "SSHKEY_TOKEN": self.config['sshkey_token'],
            "ORCHESTRATION_HOST": self.config['orchestration_host'],
            "ORCHESTRATION_USER": self.config['orchestration_user'],
            #"OPENSHIFT_CLUSTER_NAME": self.config['openshift_cluster_name'],
            #"DEPLOY_PATH": self.config['dynamic_deploy_path'],
            "KUBECONFIG_NAME": f"{self.release_name}-kubeconfig",
            "KUBEADMIN_NAME": f"{self.release_name}-kubeadmin",
            "OPENSHIFT_INSTALL_PULL_SECRET": self.ocp_pull_secret,
            "GCP_MANAGED_SERVICES_TOKEN": self.rogcp_creds,
            "AWS_REGION": self.config['aws_region_for_openshift'],
            **self._insert_kube_env()
        }

    def initialize_cluster_task(self):
        return BashOperator(
            task_id=f"initialize_cluster",
            depends_on_past=False,
            bash_command=f"echo {{ params.KUBEUSER }}; echo {{ params.KUBEPASSWORD }}; echo {{ params.KUBEURL }};",
            #retries=3,
            dag=self.dag,
            #trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=self.env
        )


    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}