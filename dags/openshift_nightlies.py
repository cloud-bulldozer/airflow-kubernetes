import json
from datetime import timedelta
from airflow import DAG
from airflow.utils.dates import days_ago
from tasks.install_cluster import task


with open("/opt/airflow/dags/repo/dags/vars/common.json") as arg_file:
    common_args = json.load(arg_file)


default_args = common_args + {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': days_ago(2),
    'email': ['airflow@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
    'openshift_version': "4.7",
    'platform': 'AWS'
    # 'queue': 'bash_queue',
    # 'pool': 'backfill',
    # 'priority_weight': 10,
    # 'end_date': datetime(2016, 1, 1),
    # 'wait_for_downstream': False,
    # 'dag': dag,
    # 'sla': timedelta(hours=2),
    # 'execution_timeout': timedelta(seconds=300),
    # 'on_failure_callback': some_function,
    # 'on_success_callback': some_other_function,
    # 'on_retry_callback': another_function,
    # 'sla_miss_callback': yet_another_function,
    # 'trigger_rule': 'all_success'
}

dag = DAG(
    'openshift_nightlies_real',
    default_args=default_args,
    description='A simple tutorial DAG',
    schedule_interval=timedelta(days=1),
)

install_cluster = task.get_task(dag, default_args["install"]["platform"], default_args["install"]["version"], default_args["install"]["config"])
