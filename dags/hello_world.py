
from datetime import timedelta

# The DAG object; we'll need this to instantiate a DAG
from airflow import DAG
# Operators; we need this to operate!
from airflow.operators.bash_operator import BashOperator
from airflow.utils.dates import days_ago
# These args will get passed on to each operator
# You can override them on a per-task basis during operator initialization
default_args = {
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
    'openshift_nightlies',
    default_args=default_args,
    description='A simple tutorial DAG',
    schedule_interval=timedelta(days=1),
)

# t1, t2 and t3 are examples of tasks created by instantiating operators
install_openshift_cluster = BashOperator(
    task_id='install_openshift_cluster',
    bash_command='date',
    dag=dag,
)

run_network_benchmarks = BashOperator(
    task_id='run_network_benchmarks',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)

run_io_benchmarks = BashOperator(
    task_id='run_io_benchmarks',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)

run_http_scale_tests = BashOperator(
    task_id='run_http_scale_tests',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)

run_cluster_scale_tests = BashOperator(
    task_id='run_http_scale_tests',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)

run_comparisons = BashOperator(
    task_id='run_comparisons',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)

cleanup_cluster = BashOperator(
    task_id='cleanup_cluster',
    depends_on_past=False,
    bash_command='sleep 5',
    retries=3,
    dag=dag,
)



dag.doc_md = __doc__

install_openshift_cluster.doc_md = """\
#### Task Documentation
You can document your task using the attributes `doc_md` (markdown),
`doc` (plain text), `doc_rst`, `doc_json`, `doc_yaml` which gets
rendered in the UI's Task Instance Details page.
![img](http://montcs.bloomu.edu/~bobmon/Semesters/2012-01/491/import%20soul.png)
"""
# templated_command = """
# {% for i in range(5) %}
#     echo "{{ ds }}"
#     echo "{{ macros.ds_add(ds, 7)}}"
#     echo "{{ params.my_param }}"
# {% endfor %}
# """

# t3 = BashOperator(
#     task_id='templated',
#     depends_on_past=False,
#     bash_command=templated_command,
#     params={'my_param': 'Parameter I passed in'},
#     dag=dag,
# )

install_openshift_cluster >> run_http_scale_tests >> [run_network_benchmarks, run_io_benchmarks] >> run_cluster_scale_tests >> run_comparisons