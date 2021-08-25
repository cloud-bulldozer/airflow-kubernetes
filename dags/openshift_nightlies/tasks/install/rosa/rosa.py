import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(dirname(abspath(dirname(__file__))))))
from util import var_loader, kubeconfig, constants
from tasks.index.status import StatusIndexer
from tasks.install.openshift import AbstractOpenshiftInstaller

from hashlib import md5
import requests

from airflow.operators.bash import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

import json

# Defines Tasks for installation of Openshift Clusters

class RosaInstaller(AbstractOpenshiftInstaller):

    def _generate_cluster_name(self):
        cluster_name = super()._generate_cluster_name()
        cluster_version = str(self.release.version).replace(".","")
        return "airflow-"+cluster_version+"-"+md5(cluster_name.encode("ascii")).hexdigest()[:4]

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation=operation)

        if (self.vars['rosa_installation_method'] == "osde2e"):
            command=f"{constants.root_dag_dir}/scripts/install/osde2e.sh -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}"
        else:
            command=f"{constants.root_dag_dir}/scripts/install/rosa.sh -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}"

        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=command,
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=self.env
        )
