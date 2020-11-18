import json
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

exec_config = {
    "KubernetesExecutor": {
        "image": "quay.io/keithwhitley4/airflow-ansible:new-ansible-3"
    }
}




def get_task(dag, platform, version, config):
    ansible_orchestrator = Variable.get("ansible_orchestrator", deserialize_json=True)
    version_secrets = Variable.get(f"openshift_install_{version}", deserialize_json=True)
    aws_creds = Variable.get("aws_creds", deserialize_json=True)
    config = {**config, **ansible_orchestrator, **version_secrets, **aws_creds}

    env = {
        "SSHKEY_TOKEN": config['sshkey_token'],
        "ORCHESTRATION_HOST": config['orchestration_host']
    }
    

    with open('/home/airflow/task.json', 'w') as json_file:
        json.dump(config, json_file, sort_keys=True, indent=4)
    
    return BashOperator(
        task_id=f"install_rhos_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/scripts/install_cluster.sh -p {platform} -v 4 -j /home/airflow/task.json",
        retries=3,
        dag=dag,
        executor_config=exec_config,
        env=env
)