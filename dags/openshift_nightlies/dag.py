import sys
import os
import logging 
import json
from datetime import timedelta
from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

# Configure Path to have the Python Module on it
sys.path.insert(0,os.path.abspath(os.path.dirname(__file__)))
from tasks.install import openshift
from tasks.benchmarks import ripsaw
from tasks.kubernetes import command
from util import var_loader, manifest, wrapper

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task.operators")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
log.addHandler(handler)

# Metadata Args
metadata_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': days_ago(2),
    'email': ['airflow@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

manifest_args = var_loader.get_manifest_vars()
default_args = {**manifest_args, **metadata_args}

dag = DAG(
    'oc_scale',
    default_args=default_args,
    description='A simple tutorial DAG',
    schedule_interval=timedelta(days=1),
)

openshift_version = default_args["tasks"]["install"]["version"]
platform = default_args["tasks"]["install"]["platform"]
profile = default_args["tasks"]["install"]["profile"]

task_config = Variable.get('oc_scale_tasks', deserialize_json=True)

installer = openshift.OpenshiftInstaller(dag, openshift_version, platform, profile)
benchmarks = ripsaw.Ripsaw(dag, openshift_version, platform, profile)



install_cluster = wrapper.ConditionalTask(dag, task_config['install'] == True, installer.get_install_task()).get_task()

cleanup_cluster = wrapper.ConditionalTask(dag, task_config['cleanup'] == True, installer.get_cleanup_task()).get_task()


benchmarks.add_benchmarks_to_dag(upstream=install_cluster, downstream=cleanup_cluster)