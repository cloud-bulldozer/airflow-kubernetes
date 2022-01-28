from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig


from airflow.operators.bash import BashOperator


# Connect Installed Cluster to PerfScale Platform to send metrics and logs. 

class PlatformConnectorTask():
    def __init__(self, dag, config: DagConfig, release: OpenshiftRelease):
        
        # General DAG Configuration
        self.dag = dag
        self.release = release
        self.config = config
        self.exec_config = executor.get_executor_config_with_cluster_access(self.config, self.release)

        # Specific Task Configuration
        self.env = {
            "THANOS_RECEIVER_URL": var_loader.get_secret("thanos_receiver_url")
        }

    def get_task(self):
        env = {**self.env, **{"KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        return BashOperator(
            task_id="connect-to-platform",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/utils/connect_to_platform.sh ",
            retries=3,
            dag=self.dag,
            env=env,
            cwd=f"{constants.root_dag_dir}/scripts/utils",
            executor_config=self.exec_config
        )