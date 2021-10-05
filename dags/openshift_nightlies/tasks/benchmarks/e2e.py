from os import environ

from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig

import json
from datetime import timedelta
from airflow.operators.bash import BashOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s




class E2EBenchmarks():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease, task_group="benchmarks"):
        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.task_group = task_group
        self.dag_config = config
        self.exec_config = executor.get_executor_config_with_cluster_access(self.dag_config, self.release)
        self.snappy_creds = var_loader.get_secret("snappy_creds", deserialize_json=True)
        self.es_gold = var_loader.get_secret("es_gold")
        self.es_server_baseline = var_loader.get_secret("es_server_baseline")

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            release=self.release, task=self.task_group)
        self.git_name=self._git_name()
        self.env = {
            "SNAPPY_DATA_SERVER_URL": self.snappy_creds['server'],
            "SNAPPY_DATA_SERVER_USERNAME": self.snappy_creds['username'],
            "SNAPPY_DATA_SERVER_PASSWORD": self.snappy_creds['password'],
            "SNAPPY_USER_FOLDER": self.git_name,
            "PLATFORM": self.release.platform,
            "TASK_GROUP": self.task_group,
            "ES_GOLD": self.es_gold,
            "ES_SERVER_BASELINE": self.es_server_baseline
        }

        if self.release.platform == "baremetal":
            self.install_vars = var_loader.build_task_vars(
                release, task="install")
            self.baremetal_install_secrets = var_loader.get_secret(
            f"baremetal_openshift_install_config", deserialize_json=True)

            self.config = {
                **self.install_vars,
                **self.baremetal_install_secrets
            }

            self.env = {
                **self.env,
                "SSHKEY_TOKEN": self.config['sshkey_token'],
                "ORCHESTRATION_USER": self.config['provisioner_user'],
                "ORCHESTRATION_HOST": self.config['provisioner_hostname']
            }
    

    def get_benchmarks(self):
        benchmarks = self._get_benchmarks(self.vars["benchmarks"])
        return benchmarks 

    def _git_name(self):
        git_username = var_loader.get_git_user()
        if git_username == 'cloud-bulldozer':
            return f"perf-ci"
        else: 
            return f"{git_username}"

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

    def _add_indexer(self, benchmark): 
        indexer = StatusIndexer(self.dag, self.dag_config, self.release, benchmark.task_id).get_index_task() 
        benchmark >> indexer 

    def _get_benchmark(self, benchmark):
        env = {**self.env, **benchmark.get('env', {}), **{"ES_SERVER": var_loader.get_secret('elasticsearch'), "KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        task_prefix=f"{self.task_group}_"
        task = BashOperator(
                task_id=f"{task_prefix if self.task_group != 'benchmarks' else ''}{benchmark['name']}",
                depends_on_past=False,
                bash_command=f"{constants.root_dag_dir}/scripts/run_benchmark.sh -w {benchmark['workload']} -c {benchmark['command']} ",
                retries=3,
                dag=self.dag,
                env=env,
                do_xcom_push=True,
                executor_config=self.exec_config
        )

        self._add_indexer(task)
        return task
