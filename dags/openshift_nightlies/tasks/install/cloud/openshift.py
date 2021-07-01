import sys
from os.path import abspath, dirname

sys.path.insert(0, dirname(dirname(dirname(abspath(dirname(__file__))))))
from util import constants
from tasks.install.openshift import AbstractOpenshiftInstaller


from airflow.operators.bash_operator import BashOperator


# Defines Tasks for installation of Openshift Clusters
class CloudOpenshiftInstaller(AbstractOpenshiftInstaller):
    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        self._setup_task(operation=operation)
        return BashOperator(
            task_id=f"{operation}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/install/cloud.sh -p {self.platform} -v {self.version} -j /tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json -o {operation}",  # noqa
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=self.env,
        )
