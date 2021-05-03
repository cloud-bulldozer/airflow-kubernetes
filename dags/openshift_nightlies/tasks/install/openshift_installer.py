import sys
import abc
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig, constants

import json
import requests

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class OpenshiftInstaller(metaclass=abc.ABCMeta):
    def __init__(self, dag, version, release_stream, platform, profile):
        self.exec_config = {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.0.0",
                            image_pull_policy="Always",
                            volume_mounts=[
                                kubeconfig.get_empty_dir_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_empty_dir_volume_mount()]
                )
            )
        }

        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. 4.6/4.7, major.minor only
        self.release_stream = release_stream # true release stream to follow. Nightlies, CI, etc. 
        self.profile = profile  # e.g. default/ovn

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="install", version=version, platform=platform, profile=profile)

        # Airflow Variables
        self.ansible_orchestrator = Variable.get(
            "ansible_orchestrator", deserialize_json=True)

        self.release_stream_base_url = Variable.get("release_stream_base_url")
        self.install_secrets = Variable.get(
            f"openshift_install_config", deserialize_json=True)
        self.aws_creds = Variable.get("aws_creds", deserialize_json=True)
        self.gcp_creds = Variable.get("gcp_creds", deserialize_json=True)
        self.azure_creds = Variable.get("azure_creds", deserialize_json=True)
        self.openstack_creds = Variable.get("openstack_creds", deserialize_json=True)

    def _setup_task(self, operation="install"):
        self.playbook_operations = {}
        if operation == "install":
            self.playbook_operations = {"openshift_cleanup": True, "openshift_debug_config": False,
                                   "openshift_install": True, "openshift_post_config": True, "openshift_post_install": True}
        else:
            self.playbook_operations = {"openshift_cleanup": True, "openshift_debug_config": False,
                                   "openshift_install": False, "openshift_post_config": False, "openshift_post_install": False}

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        self.config = {
            **self.vars,
            **self.ansible_orchestrator,
            **self.install_secrets,
            **self.aws_creds,
            **self.gcp_creds,
            **self.azure_creds,
            **self.openstack_creds,
            **self.playbook_operations,
            **var_loader.get_latest_release_from_stream(self.release_stream_base_url, self.release_stream),
            **{ "es_server": var_loader.get_elastic_url() }
        }

        self.git_user = var_loader.get_git_user()
        if self.git_user == 'cloud-bulldozer':
            self.config['openshift_cluster_name'] = f"ci-{self.version}-{self.platform}-{self.profile}"
        else: 
            self.config['openshift_cluster_name'] = f"{self.git_user}-{self.version}-{self.platform}-{self.profile}"

        self.config['dynamic_deploy_path'] = f"{self.config['openshift_cluster_name']}"
        self.config['kubeconfig_path'] = f"/root/{self.config['dynamic_deploy_path']}/auth/kubeconfig"
        # Required Environment Variables for Install script
        env = {
            "SSHKEY_TOKEN": self.config['sshkey_token'],
            "ORCHESTRATION_HOST": self.config['orchestration_host'],
            "ORCHESTRATION_USER": self.config['orchestration_user'],
            "OPENSHIFT_CLUSTER_NAME": self.config['openshift_cluster_name'],
            "DEPLOY_PATH": self.config['dynamic_deploy_path'],
            "KUBECONFIG_NAME": f"{self.version}-{self.platform}-{self.profile}-kubeconfig",
            **self._insert_kube_env()
        }

    
    def get_install_task(self):
        return self._get_task(operation="install")

    def get_cleanup_task(self):
        # trigger_rule = "all_done" means this task will run when every other task has finished, whether it fails or succeededs
        return self._get_task(operation="cleanup")

    # Create Airflow Task for Install/Cleanup steps
    @abc.abstractmethod
    def _get_task(self, operation="install", trigger_rule="all_success"):
        pass

    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}
