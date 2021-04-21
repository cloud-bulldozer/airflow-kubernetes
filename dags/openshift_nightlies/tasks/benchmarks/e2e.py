import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig, constants
from tasks.index.status import StatusIndexer

import json
from datetime import timedelta
from airflow.operators.bash_operator import BashOperator
from airflow.operators.subdag_operator import SubDagOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s




class E2EBenchmarks():
    def __init__(self, dag, version, release_stream, latest_release, platform, profile, default_args):

        self.exec_config = {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.0.0",
                            image_pull_policy="Always",
                            volume_mounts=[
                                kubeconfig.get_kubeconfig_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_kubeconfig_volume(
                        version, platform, profile)]
                )
            )
        }

        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. stable/.next/.future
        self.release_stream = release_stream
        self.latest_release = latest_release # latest relase from the release stream
        self.profile = profile  # e.g. default/ovn
        self.default_args = default_args

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="benchmarks", version=version, platform=platform, profile=profile)
        self.env = {
            "OPENSHIFT_CLIENT_LOCATION": self.latest_release["openshift_client_location"]
        }

        


    def get_benchmarks(self):
        return self._get_benchmarks(self.vars["benchmarks"])

    def _get_benchmarks(self, benchmarks):
        for index, benchmark in enumerate(benchmarks):
            if isinstance(benchmark, dict):
                benchmarks[index] = self._get_benchmark(benchmark)
            elif isinstance(benchmark, list):
                benchmarks[index] = self._get_benchmarks(benchmark)
        return benchmarks

    def _get_benchmark(self, benchmark):
        env = {**self.env, **benchmark.get('env', {}), **{"ES_SERVER": var_loader.get_elastic_url()}}

        benchmark_task = BashOperator(
            task_id=f"{benchmark['name']}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/run_benchmark.sh -w {benchmark['workload']} -c {benchmark['command']} ",
            retries=0,
            dag=self.dag,
            env=env,
            executor_config=self.exec_config
        )

        
        indexer = StatusIndexer(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile, benchmark['name']).get_index_task() 
        
        
        benchmark_task >> indexer
        return benchmark_task
