from airflow.operators.bash_operator import BashOperator




def get_task(dag, platform, version, operation="uperf"):
    return BashOperator(
        task_id=f"{operation}_rhos_{version}_{platform}",
        depends_on_past=False,
        bash_command=f"ls",
        retries=0,
        dag=dag,
    )