from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig


from airflow.operators.bash import BashOperator


# Connect Installed Cluster to PerfScale Platform to send metrics and logs. 

class PlatformConnectorTask():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease, task_group=""):
        
        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.task_group = task_group
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release, self.task_group)

        # Specific Task Configuration
        self.env = {
            "REL_PLATFORM": self.release.platform,
            "THANOS_RECEIVER_URL": var_loader.get_secret("thanos_receiver_url"),
            "LOKI_RECEIVER_URL": var_loader.get_secret("loki_receiver_url")
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

    def get_task(self):
        task_prefix=f"{self.task_group}-"
        return BashOperator(
            task_id=f"{task_prefix if self.task_group != '' else ''}connect-to-platform",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/utils/connect_to_platform.sh ",
            retries=3,
            dag=self.dag,
            env=self.env,
            cwd=f"{constants.root_dag_dir}/scripts/utils",
            executor_config=self.exec_config
        )