import json
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

exec_config = {
    "KubernetesExecutor": {
        "image": "quay.io/keithwhitley4/airflow-ansible:local-inv"
    }
}

aws = Variable.get('aws', deserialize_json=True)


def get_task(dag, platform, version, config):
    config = {**config, **aws}
    
    return BashOperator(
        task_id=f"install_openshift_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/tasks/install_cluster/scripts/install_cluster.sh -p {platform} -v {version} -j '{json.dumps(config)}'",
        retries=3,
        dag=dag,
        executor_config=exec_config
)