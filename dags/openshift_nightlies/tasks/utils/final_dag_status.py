from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from common.models.dag_config import DagConfig


from airflow.operators.python import PythonOperator


def final_status(**kwargs):
    failed_tasks=[]
    for task_instance in kwargs['dag_run'].get_task_instances():
        if "index" in task_instance.task_id:
            continue
        elif task_instance.current_state() != 'success' and task_instance.task_id != kwargs['task_instance'].task_id:
            failed_tasks.append(task_instance.task_id)

    if len(failed_tasks) > 0:
        raise Exception("Tasks {} failed. Failing this DAG run".format(failed_tasks))



def get_task(dag):
    return PythonOperator(
        task_id='final_status',
        provide_context=True,
        python_callable=final_status,
        trigger_rule='all_done',
        retries=0,
        dag=dag,
    )
