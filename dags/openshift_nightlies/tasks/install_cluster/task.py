import json
from airflow.operators.bash_operator import BashOperator

def get_task(dag, platform, version, config): 
    return BashOperator(
    task_id=f"install_openshift_{version}_{platform}",
    depends_on_past=False,
    bash_command='sleep 5; ls; sleep 5',
    retries=3,
    dag=dag,
)