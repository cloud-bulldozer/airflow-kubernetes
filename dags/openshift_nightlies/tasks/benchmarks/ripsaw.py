import json
import sys
from os.path import abspath, dirname
from os import environ
from datetime import timedelta
from airflow.operators.bash_operator import BashOperator
from airflow.operators.subdag_operator import SubDagOperator
from airflow.models import Variable
from airflow.models import DAG


sys.path.insert(0,dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig



class Ripsaw():
    def __init__(self, dag, version, platform, profile, default_args): 

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
        self.default_args = default_args
        
        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(task="benchmarks", version=version, platform=platform, profile=profile)
        self.version_secrets = Variable.get(f"openshift_install_{version}", deserialize_json=True)
        self.env = {
            "OPENSHIFT_CLIENT_LOCATION": self.version_secrets["openshift_client_location"]
        }

    def get_benchmarks(self):
        return self._get_benchmarks(self.vars["benchmarks"])

    def _get_benchmarks(self, benchmarks):
        for index, benchmark in enumerate(benchmarks):
            if isinstance(benchmark, str):
                benchmarks[index] = self._get_benchmark(benchmark)
            elif isinstance(benchmark, list):
                benchmarks[index] = self._get_benchmarks(benchmark)
        return benchmarks
        
    def _get_benchmark(self, benchmark):
        return BashOperator(
            task_id=f"{benchmark}",
            depends_on_past=False,
            bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/scripts/run_benchmark.sh -b uperf_smoke",
            retries=0,
            dag=self.dag,
            env=self.env,
            executor_config=self.exec_config
    )