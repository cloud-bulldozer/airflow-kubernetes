import json
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

exec_config = {
    "KubernetesExecutor": {
        "image": "quay.io/keithwhitley4/airflow-ansible:new-ansible-3"
    }
}




def get_task(dag, platform, version, config):
    platform_secrets = Variable.get(platform, deserialize_json=True)
    config = {**config, **platform_secrets}

    env = {
        "SSHKEY_TOKEN": platform_secrets['sshkey_token'],
        "ORCHESTRATION_HOST": platform_secrets['orchestration_host']
    }
    

    with open('/home/airflow/task.json', 'w') as json_file:
        json.dump(config, json_file)
    
    return BashOperator(
        task_id=f"install_openshift_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/scripts/install_cluster.sh -p {platform} -v {version} -j /home/airflow/task.json",
        retries=3,
        dag=dag,
        executor_config=exec_config,
        env=env
)