from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.tasks.install.openshift import AbstractOpenshiftInstaller

import json
import requests

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class CloudOpenshiftInstaller(AbstractOpenshiftInstaller):
    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/install/cloud.sh -p {self.release.platform} -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}",
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=self.env
        )
