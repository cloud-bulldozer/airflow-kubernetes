import sys
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
class ScaleCiDeploy():
    def __init__(self, dag, version, release_stream, platform, profile):
        super().__init__(self, dag, version, release_stream, platform, profile)

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation)
        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json", 'w') as json_file:
            json.dump(self.config, json_file, sort_keys=True, indent=4)

        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/install_cluster/scale_ci_deploy -p {self.platform} -v {self.version} -j /tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json -o {operation}",
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )
