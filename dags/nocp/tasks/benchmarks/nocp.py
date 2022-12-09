from os import environ

from nocp.util import constants
from nocp.util import var_loader as nocp_var_loader
from common.models.dag_config import DagConfig
from nocp.util import var_loader

import json
from datetime import timedelta
from airflow.operators.bash import BashOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s




class NOCPBenchmarks():
    def __init__(self, app, dag, config: DagConfig, task_group="benchmarks"):
        # General DAG Configuration
        self.app = app
        self.dag = dag
        self.task_group = task_group
        self.dag_config = config
        self.snappy_creds = var_loader.get_secret("snappy_creds", deserialize_json=True)
        self.es_server_baseline = var_loader.get_secret("es_server_baseline")

        # Specific Task Configuration
        self.vars = nocp_var_loader.build_nocp_task_vars(
            app, task=self.task_group)
        self.git_name=self._git_name()
        self.env = {
            "SNAPPY_DATA_SERVER_URL": self.snappy_creds['server'],
            "SNAPPY_DATA_SERVER_USERNAME": self.snappy_creds['username'],
            "SNAPPY_DATA_SERVER_PASSWORD": self.snappy_creds['password'],
            "SNAPPY_USER_FOLDER": self.git_name,
            "GIT_USER": self.git_name,
            "TASK_GROUP": self.task_group,
            "ES_SERVER_BASELINE": self.es_server_baseline,
        }
        self.env.update(self.dag_config.dependencies)
        if self.app == "ocm":
            self.ocm_creds = var_loader.get_secret("ocm_creds", deserialize_json=True)
            self.aws_creds = var_loader.get_secret("aws_creds", deserialize_json=True)
            self.env = {
                **self.env,
                "SSHKEY_TOKEN": self.ocm_creds['sshkey_token'],
                "ORCHESTRATION_USER": self.ocm_creds['orchestration_user'],
                "ORCHESTRATION_HOST": self.ocm_creds['orchestration_host'],
                "OCM_TOKEN": self.ocm_creds['ocm_token'],
                "PROM_TOKEN": self.ocm_creds['prometheus_token'],
                "AWS_ACCESS_KEY_ID": self.aws_creds['aws_access_key_id'],
                "AWS_SECRET_ACCESS_KEY": self.aws_creds['aws_secret_access_key'],
                "AWS_DEFAULT_REGION": self.aws_creds['aws_region_for_openshift'],
                "AWS_ACCOUNT_ID": self.aws_creds['aws_account_id']
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

    def _add_cleaner(self, benchmark, env):
        if self.app == "ocm":
            command = f'UUID={{{{ ti.xcom_pull("{benchmark.task_id}") }}}} {constants.root_dag_dir}/scripts/run_ocm_benchmark.sh -o cleanup'

        cleaner = BashOperator(
            task_id=f"cleanup-{benchmark.task_id}",
            depends_on_past=False,
            bash_command=command,
            retries=0,
            dag=self.dag,
            trigger_rule="all_done",
            env=env
        )

        benchmark >> cleaner

    def _get_benchmark(self, benchmark):
        env = {**self.env, **benchmark.get('env', {}), **{"ES_SERVER": var_loader.get_secret('elasticsearch')}}
        # Fetch variables from a secret with the name <DAG_NAME>-<TASK_NAME>
        task_variables = var_loader.get_secret(f"{self.dag.dag_id}-{benchmark['name']}", True, False)
        env.update(task_variables)
        task_prefix=f"{self.task_group}-"
        timeout = 21600
        bash_command = None
        if self.app == "ocm":
            bash_command = f"{constants.root_dag_dir}/scripts/run_ocm_benchmark.sh -o ocm-api-load"
            timeout = 28800

        task = BashOperator(
                task_id=f"{task_prefix if self.task_group != 'benchmarks' else ''}{benchmark['name']}",
                depends_on_past=False,
                bash_command=bash_command,
                retries=0,
                trigger_rule=benchmark.get("trigger_rule", "all_success"),
                dag=self.dag,
                env=env,
                do_xcom_push=True,
                execution_timeout=timedelta(seconds=timeout),
        )

        if self.app == "ocm":
            self._add_cleaner(task, env)

        return task
