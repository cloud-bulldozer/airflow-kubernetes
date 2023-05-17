from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig

from airflow.operators.bash import BashOperator


class Diagnosis():

    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):
        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release)
        self.snappy_creds = var_loader.get_secret("snappy_creds", deserialize_json=True)

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            release=self.release, task="utils")["must_gather"]
        self.git_name = self._git_name()
        self.env = {
            "SNAPPY_DATA_SERVER_URL": self.snappy_creds['server'],
            "SNAPPY_DATA_SERVER_USERNAME": self.snappy_creds['username'],
            "SNAPPY_DATA_SERVER_PASSWORD": self.snappy_creds['password'],
            "SNAPPY_USER_FOLDER": self.git_name

        }
        self.env.update(self.config.dependencies)

    def _git_name(self):
        git_username = var_loader.get_git_user()
        if git_username == 'cloud-bulldozer':
            return "perf-ci"
        else:
            return f"{git_username}"

    def get_must_gather(self, task_id):
        env = {**self.env, **self.vars.get('env', {}), **{"ES_SERVER": var_loader.get_secret('elasticsearch')}, **{"KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        return BashOperator(
            task_id=task_id,
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/utils/run_scale_ci_diagnosis.sh -w {self.vars['workload']} -c {self.vars['command']} ",
            retries=3,
            dag=self.dag,
            env=env,
            executor_config=self.exec_config,
            trigger_rule="one_failed"
        )
