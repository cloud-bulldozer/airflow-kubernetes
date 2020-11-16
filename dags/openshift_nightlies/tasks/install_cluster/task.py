import json
from airflow.operators.bash_operator import BashOperator

exec_config = {
    "KubernetesExecutor": {
        "image": "quay.io/keithwhitley4/airflow:latest"
    }
}

def get_task(dag, platform, version, config):
    
    return BashOperator(
        task_id=f"install_openshift_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/tasks/install_cluster/scripts/install_cluster.sh -p {platform} -v {version} -j {config}",
        retries=3,
        dag=dag,
        executor_config=exec_config
)