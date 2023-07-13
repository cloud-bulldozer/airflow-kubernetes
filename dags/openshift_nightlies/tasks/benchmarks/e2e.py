from os import environ

from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.tasks.index.status import StatusIndexer
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig

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
        self.snappy_creds = var_loader.get_secret("snappy_creds", deserialize_json=True)
        self.es_server_baseline = var_loader.get_secret("es_server_baseline")
        self.gsheet = var_loader.get_secret("gsheet_key")

        # Write gsheet data to /tmp/key.json
        if len(self.gsheet) > 1 :
            f = open("/tmp/key.json","w")
            f.write(json.dumps(self.gsheet))
            f.close()

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
            "ES_SERVER_BASELINE": self.es_server_baseline

        }
        self.env.update(self.dag_config.dependencies)

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

        if self.release.platform == "rosa":
            self.rosa_creds = var_loader.get_secret("rosa_creds", deserialize_json=True)
            self.aws_creds = var_loader.get_secret("aws_creds", deserialize_json=True)
            self.ocm_creds = var_loader.get_secret("ocm_creds", deserialize_json=True)
            self.environment = self.vars["environment"] if "environment" in self.vars else "staging"
            self.env = {
                **self.env,
                "ROSA_CLUSTER_NAME": release._generate_cluster_name(),
                "ROSA_ENVIRONMENT": self.environment,
                "ROSA_TOKEN": self.rosa_creds['rosa_token_'+self.environment],
                "AWS_ACCESS_KEY_ID": self.aws_creds['aws_access_key_id'],
                "AWS_SECRET_ACCESS_KEY": self.aws_creds['aws_secret_access_key'],
                "AWS_DEFAULT_REGION": self.aws_creds['aws_region_for_openshift'],
                "AWS_ACCOUNT_ID": self.aws_creds['aws_account_id'],
                "OCM_TOKEN": self.ocm_creds['ocm_token']
            }
            self.install_vars = var_loader.build_task_vars(
                release, task="install")
            if self.install_vars['rosa_hcp'] == "true":
                cluster_name = release._generate_cluster_name()
                self.env = {
                    **self.env,
                    "MGMT_CLUSTER_NAME": f"{self.install_vars['staging_mgmt_cluster_name']}.*",
                    "SVC_CLUSTER_NAME": f"{self.install_vars['staging_svc_cluster_name']}.*",
                    "MGMT_KUBECONFIG_SECRET": "staging-mgmt-cluster-kubeconfig",
                    **self._insert_kube_env()
                }

        if self.release.platform == "hypershift":
            mgmt_cluster_name = release._generate_cluster_name()
            self.env = {
                **self.env,
                "THANOS_RECEIVER_URL": var_loader.get_secret("thanos_receiver_url"),
                "PROM_URL": var_loader.get_secret("thanos_querier_url"),
                "MGMT_CLUSTER_NAME": f"{mgmt_cluster_name}.*",
                "HOSTED_CLUSTER_NS": f"clusters-hcp-{mgmt_cluster_name}-{self.task_group}",
                "MGMT_KUBECONFIG_SECRET": f"{release.get_release_name()}-kubeconfig",
                **self._insert_kube_env()
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
        indexer = StatusIndexer(self.dag, self.dag_config, self.release, benchmark.task_id, task_group=self.task_group).get_index_task()
        benchmark >> indexer

    def _get_benchmark(self, benchmark):
        env = {**self.env, **benchmark.get('env', {}), **{"ES_SERVER": var_loader.get_secret('elasticsearch'), "KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        # Fetch variables from a secret with the name <DAG_NAME>-<TASK_NAME>
        task_variables = var_loader.get_secret(f"{self.dag.dag_id}-{benchmark['name']}", True, False)
        env.update(task_variables)
        task_prefix=f"{self.task_group}-"
        if 'executor_image' in benchmark:
            self.exec_config = executor.get_executor_config_with_cluster_access(self.dag_config, self.release, executor_image=benchmark['executor_image'], task_group=self.task_group)
        else:
            self.exec_config = executor.get_executor_config_with_cluster_access(self.dag_config, self.release, task_group=self.task_group)
        if 'custom_cmd' in benchmark:
            # Surround argument by single quotes to avoid variable substitution
            cmd = f"{constants.root_dag_dir}/scripts/run_benchmark.sh -c '{benchmark['custom_cmd']}'"
        else:
            cmd = f"{constants.root_dag_dir}/scripts/run_benchmark.sh -w {benchmark['workload']} -c {benchmark['command']} "
        task = BashOperator(
                task_id=f"{task_prefix if self.task_group != 'benchmarks' else ''}{benchmark['name']}",
                depends_on_past=False,
                bash_command=cmd,
                retries=0,
                trigger_rule=benchmark.get("trigger_rule", "all_success"),
                dag=self.dag,
                env=env,
                do_xcom_push=True,
                execution_timeout=timedelta(seconds=21600),
                executor_config=self.exec_config
        )
        self._add_indexer(task)
        return task

    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}
