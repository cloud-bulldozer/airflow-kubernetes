import sys
import os
import logging 
import json
from datetime import timedelta
from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.operators.bash_operator import BashOperator

# Configure Path to have the Python Module on it
sys.path.insert(0,os.path.abspath(os.path.dirname(__file__)))
from tasks.install import openshift 
from tasks.benchmarks import ripsaw
from util import var_loader

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/openshift_nightlies"

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
    'openshift_version': "4.7",
    'platform': 'AWS'
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

installer = openshift.OpenshiftInstaller(dag, platform, openshift_version, profile)


install_cluster = installer.get_install_task()
cleanup_cluster = installer.get_cleanup_task()

uperf = ripsaw.get_task(dag, platform, openshift_version, operation="uperf")
http = ripsaw.get_task(dag, platform, openshift_version, operation="http")
http_copy = ripsaw.get_task(dag, platform, openshift_version, operation="http_post")
scale_up = ripsaw.get_task(dag, platform, openshift_version, operation="scale_up")
scale_down = ripsaw.get_task(dag, platform, openshift_version, operation="scale_down")
cluster_density = ripsaw.get_task(dag, platform, openshift_version, "cluster_density")
kubelet_density = ripsaw.get_task(dag, platform, openshift_version, "kubelet_density") 

install_cluster >> [http, uperf] >> scale_up >> [http_copy, cluster_density, kubelet_density] >> scale_down >> cleanup_cluster