import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig, constants

import json
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class OpenshiftInstaller():
    def __init__(self, dag, version, platform, profile):

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
        self.version = version  # e.g. stable/.next/.future
        self.profile = profile  # e.g. default/ovn

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="install", version=version, platform=platform, profile=profile)

        # Airflow Variables
        self.ansible_orchestrator = Variable.get(
            "ansible_orchestrator", deserialize_json=True)
        self.version_secrets = Variable.get(
            f"openshift_install_{version}", deserialize_json=True)
        self.aws_creds = Variable.get("aws_creds", deserialize_json=True)

    def get_install_task(self):
        return self._get_task(operation="install")

    def get_cleanup_task(self):
        # trigger_rule = "all_done" means this task will run when every other task has finished, whether it fails or succeededs
        return self._get_task(operation="cleanup")

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        playbook_operations = {}
        if operation == "install":
            playbook_operations = {"openshift_cleanup": True, "openshift_debug_config": True,
                                   "openshift_install": True, "openshift_post_config": True, "openshift_post_install": True}
        else:
            playbook_operations = {"openshift_cleanup": True, "openshift_debug_config": False,
                                   "openshift_install": False, "openshift_post_config": False, "openshift_post_install": False}

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        config = {**self.vars, **self.ansible_orchestrator, **
                  self.version_secrets, **self.aws_creds, **playbook_operations}

        config['kubeconfig_path'] = f"/root/scale-ci-{config['openshift_cluster_name']}-{self.platform}/auth/kubeconfig"
        # Required Environment Variables for Install script
        env = {
            "SSHKEY_TOKEN": config['sshkey_token'],
            "ORCHESTRATION_HOST": config['orchestration_host'],
            "ORCHESTRATION_USER": config['orchestration_user'],
            "OPENSHIFT_CLUSTER_NAME": config['openshift_cluster_name'],
            "KUBECONFIG_NAME": f"{self.version}-{self.platform}-{self.profile}-kubeconfig",
            **self._insert_kube_env()
        }

        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json", 'w') as json_file:
            json.dump(config, json_file, sort_keys=True, indent=4)

        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/install_cluster.sh -p {self.platform} -v {self.version} -j /tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json -o {operation}",
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )

    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}
