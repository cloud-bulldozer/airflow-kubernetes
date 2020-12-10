import json
import sys
from os.path import abspath, dirname
from os import environ
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

sys.path.insert(0,dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig

class KubectlCommand():
    def __init__(self, dag, version, platform, profile): 

        # Which Image do these tasks use
        self.exec_config = {
            "KubernetesExecutor": {
                "image": "quay.io/keithwhitley4/airflow-ansible:kubectl",
                "volumes": [kubeconfig.get_kubeconfig_volume(version, platform, profile)],
                "volume_mounts": [kubeconfig.get_kubeconfig_volume_mount()]
            }
        }

        # General DAG Configuration 
        self.dag = dag
        self.platform = platform # e.g. aws
        self.version = version # e.g. stable/.next/.future
        self.profile = profile # e.g. default/ovn
        
        
        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(task="kubernetes", version=version, platform=platform, profile=profile)

    def get_task(self):
        return BashOperator(
            task_id=f"kubecommand_rhos_{self.version}_{self.platform}",
            depends_on_past=False,
            bash_command=f"{self.vars['binary']} {self.vars['command']}",
            retries=0,
            dag=self.dag,
            executor_config=self.exec_config
        )

