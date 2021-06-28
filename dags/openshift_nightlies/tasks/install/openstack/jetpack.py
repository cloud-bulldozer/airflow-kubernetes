import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(dirname(abspath(dirname(__file__))))))
from util import var_loader, kubeconfig, constants
from tasks.install.openshift import AbstractOpenshiftInstaller

import json
import requests

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class OpenstackJetpackInstaller(AbstractOpenshiftInstaller):
    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/install/jetpack.sh -j /tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json -o {operation}",
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=self.env
        )
    
    def _setup_task(self, operation="install"):
        self.config = {**self.config, **self._get_playbook_operations(operation)}
        self.config['openshift_cluster_name'] = self.openstack_creds["ocp_cluster_name"]
        self.config['dynamic_deploy_path'] = self.openstack_creds["ocp_cluster_name"]
        self.config['kubeconfig_path'] = "home/stack/" + self.openstack_creds["ocp_cluster_name"] + "/auth/kubeconfig"
        self.env = {
            "SSHKEY_TOKEN": self.config['sshkey_token'],
            "ORCHESTRATION_HOST": self.config['orchestration_host'],
            "ORCHESTRATION_USER": self.config['orchestration_user'],
            "OPENSHIFT_CLUSTER_NAME": self.config['openshift_cluster_name'],
            "DEPLOY_PATH": self.config['dynamic_deploy_path'],
            "KUBECONFIG_NAME": f"{self.version}-{self.platform}-{self.profile}-kubeconfig",
            "KUBEADMIN_NAME": f"{self.version}-{self.platform}-{self.profile}-kubeadmin",
            "OPENSHIFT_INSTALL_PULL_SECRET": self.ocp_pull_secret,
            **self._insert_kube_env()
        }

        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json", 'w') as json_file:
            json.dump(self.config, json_file, sort_keys=True, indent=4)   


    def _get_playbook_operations(self, operation):
        if operation == "install":
            return {"openshift_cleanup": True, "openshift_debug_config": False,
                                   "openshift_install": False, "openshift_post_config": True, "openshift_post_install": True}
        else:
            return {"openshift_cleanup": True, "openshift_debug_config": False,
                                   "openshift_install": False, "openshift_post_config": False, "openshift_post_install": False}
    
