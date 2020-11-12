import json
from airflow.operators.bash_operator import BashOperator

def get_task(dag, platform, version, config): 
    return BashOperator(
    task_id=f"install_openshift__{version}_{platform}",
    depends_on_past=False,
    bash_command='ls',
    retries=3,
    dag=dag,
)