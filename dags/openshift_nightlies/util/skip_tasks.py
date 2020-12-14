from airflow.operators.dummy_operator import DummyOperator

def get_skip_task(dag, task_id):
    return DummyOperator(dag=dag, task_id=task_id)