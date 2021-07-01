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
    def __init__(self, dag, version, release_stream, platform, profile, default_args):

        self.exec_config = var_loader.get_executor_config_with_cluster_access(version, platform, profile)

        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. stable/.next/.future
        self.release_stream = release_stream
        self.profile = profile  # e.g. default/ovn
        self.default_args = default_args

        # Airflow Variables
        self.SNAPPY_DATA_SERVER_URL = Variable.get("SNAPPY_DATA_SERVER_URL")
        self.SNAPPY_DATA_SERVER_USERNAME = Variable.get("SNAPPY_DATA_SERVER_USERNAME")
        self.SNAPPY_DATA_SERVER_PASSWORD = Variable.get("SNAPPY_DATA_SERVER_PASSWORD")

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="benchmarks", version=version, platform=platform, profile=profile)
        self.git_name=self._git_name()
        self.env = {
            "SNAPPY_DATA_SERVER_URL": self.SNAPPY_DATA_SERVER_URL,
            "SNAPPY_DATA_SERVER_USERNAME": self.SNAPPY_DATA_SERVER_USERNAME,
            "SNAPPY_DATA_SERVER_PASSWORD": self.SNAPPY_DATA_SERVER_PASSWORD,
            "SNAPPY_USER_FOLDER": self.git_name
        }

        
    def _git_name(self):
        git_username = var_loader.get_git_user()
        if git_username == 'cloud-bulldozer':
            return f"perf-ci"
        else: 
            return f"{git_username}"

    def get_benchmarks(self):
        benchmarks = self._get_benchmarks(self.vars["benchmarks"])
        with TaskGroup("Index Results", prefix_group_id=False, dag=self.dag) as post_steps:
            indexers = self._add_indexers(benchmarks)
        return benchmarks

    def _get_benchmarks(self, benchmarks):
        for index, benchmark in enumerate(benchmarks):
            if 'benchmarks' not in benchmark:
                benchmarks[index] = self._get_benchmark(benchmark)
            elif 'group' in benchmark:
                with TaskGroup(benchmark['group'], prefix_group_id=False, dag=self.dag) as task_group:
                    benchmarks[index] = self._get_benchmarks(benchmark['benchmarks'])
            else: 
                benchmarks[index] = self._get_benchmarks(benchmark['benchmarks'])
        return benchmarks

    def _add_indexers(self, benchmarks):
            for index, benchmark in enumerate(benchmarks):
                if isinstance(benchmark, BashOperator):
                    self._add_indexer(benchmark)
                elif isinstance(benchmark, list):
                    self._add_indexers(benchmark)

    def _add_indexer(self, benchmark): 
        indexer = StatusIndexer(self.dag, self.version, self.release_stream, self.platform, self.profile, benchmark.task_id).get_index_task() 
        benchmark >> indexer 

    def _get_benchmark(self, benchmark):
        env = {**self.env, **benchmark.get('env', {}), **{"ES_SERVER": var_loader.get_elastic_url()}, **{"KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        return BashOperator(
            task_id=f"{benchmark['name']}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/run_benchmark.sh -w {benchmark['workload']} -c {benchmark['command']} ",
            retries=3,
            dag=self.dag,
            env=env,
            executor_config=self.exec_config
        )
