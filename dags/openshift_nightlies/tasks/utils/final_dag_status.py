from os import environ
from openshift_nightlies.util import var_loader, executor, constants
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig


from airflow.operators.python import PythonOperator


def final_status(**kwargs):
    for task_instance in kwargs['dag_run'].get_task_instances():
        if task_instance.current_state() != 'success' and task_instance.task_id != kwargs['task_instance'].task_id:
            raise Exception("Task {} failed. Failing this DAG run".format(task_instance.task_id))



def get_task(dag):
    return PythonOperator(
        task_id='final_status',
        provide_context=True,
        python_callable=final_status,
        trigger_rule='all_done',
        dag=dag,
    )