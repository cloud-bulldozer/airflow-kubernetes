import json
import sys
from os.path import abspath, dirname
from os import environ
from datetime import timedelta
from airflow.operators.bash_operator import BashOperator
from airflow.operators.subdag_operator import SubDagOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.helpers import chain

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

        self.benchmark_subdag = DAG(
            dag_id=f"{dag.dag_id}.benchmarks",
            default_args=default_args,
            schedule_interval=timedelta(days=1)
        )
        
        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(task="benchmarks", version=version, platform=platform, profile=profile)

    
    def create_subdag(self): 
        benchmarks = self.vars["benchmarks"]
        benchmark_operators = self._get_benchmarks(benchmarks)
        chain(*benchmark_operators)
        return SubDagOperator(
            task_id='benchmarks',
            subdag=self.benchmark_subdag,
            dag=self.dag
        )


    def _get_benchmarks(self, benchmarks):
        for index, benchmark in enumerate(benchmarks):
            if isinstance(benchmark, str):
                benchmarks[index] = self._get_benchmark_operator(benchmark)
            elif isinstance(benchmark, list):
                benchmarks[index] = self._get_benchmarks(benchmark)
        return benchmarks
        
    def _get_benchmark_operator(self, benchmark):
        return BashOperator(
            task_id=f"{benchmark}_rhos_{self.version}_{self.platform}",
            depends_on_past=False,
            bash_command=f"ls",
            retries=0,
            dag=self.benchmark_subdag,
    )

def get_task(dag, platform, version, operation="uperf"):
    return BashOperator(
        task_id=f"{operation}_rhos_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"ls",
        retries=0,
        dag=dag,
    )