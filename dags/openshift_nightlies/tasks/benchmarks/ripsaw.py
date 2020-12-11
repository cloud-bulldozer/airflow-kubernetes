import json
import sys
from os.path import abspath, dirname
from os import environ
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from airflow.utils.helpers import chain

sys.path.insert(0,dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig



class Ripsaw():
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
        self.vars = var_loader.build_task_vars(task="benchmarks", version=version, platform=platform, profile=profile)


    def add_benchmarks_to_dag(self, upstream, downstream):
        benchmarks = self.vars["benchmarks"]
        print(benchmarks)
        benchmark_operators = self._get_benchmarks(benchmarks)
        print(*benchmark_operators)
        print(benchmark_operators[1][1])
        chain(upstream, *benchmark_operators, downstream)

        

    def _get_benchmarks(self, benchmarks):
        for index, benchmark in enumerate(benchmarks):
            if isinstance(benchmark, str):
                benchmarks[index] = self._get_benchmark_operator(benchmark)
            elif isinstance(benchmark, list):
                benchmark[index] = self._get_benchmarks(benchmark)
        return benchmarks
        
    def _get_benchmark_operator(self, benchmark):
        return BashOperator(
            task_id=f"{benchmark}_rhos_{self.version}_{self.platform}",
            depends_on_past=False,
            bash_command=f"ls",
            retries=0,
            dag=self.dag,
    )

def get_task(dag, platform, version, operation="uperf"):
    return BashOperator(
        task_id=f"{operation}_rhos_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"ls",
        retries=0,
        dag=dag,
    )