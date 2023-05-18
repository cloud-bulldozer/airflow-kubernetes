from airflow.operators.python import PythonOperator
from airflow import exceptions


def final_status(**kwargs):
    failed_tasks = []
    for task_instance in kwargs['dag_run'].get_task_instances():
        if task_instance.current_state() == 'failed' and task_instance.task_id != kwargs['task_instance'].task_id:
            failed_tasks.append(task_instance.task_id)

    if len(failed_tasks) > 0:
        kwargs['ti'].xcom_push(key="failed_tasks", value=" ".join(failed_tasks))
        raise exceptions.AirflowFailException(f"Tasks {failed_tasks} failed. Failing this DAG run")


def get_task(dag):
    return PythonOperator(
        task_id='final_status',
        python_callable=final_status,
        trigger_rule='all_done',
        retries=0,
        dag=dag,
    )
