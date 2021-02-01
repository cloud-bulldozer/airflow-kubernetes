import sys
import os
import logging 
import json
from datetime import timedelta
from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.utils.helpers import chain
from airflow.operators.bash_operator import BashOperator

# Configure Path to have the Python Module on it
sys.path.insert(0,os.path.abspath(os.path.dirname(__file__)))
from tasks.install import openshift
from tasks.benchmarks import ripsaw
from util import var_loader, manifest

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task.operators")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
log.addHandler(handler)

class OpenshiftNightlyDAG():
    def __init__(self, version, platform, profile):
        self.platform = platform
        self.version = version
        self.profile = profile
        self.release = f"{self.version}_{self.platform}_{self.profile}"
        self.metadata_args = {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': days_ago(0),
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 1,
            'release': self.release,
            'retry_delay': timedelta(minutes=5),
        }
        self.dag = DAG(
            self.release,
            default_args=self.metadata_args,
            description=f"DAG for Openshift Nightly builds {self.release}",
            schedule_interval=timedelta(days=1),
        )
    
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        cleanup_cluster = installer.get_cleanup_task()
        with TaskGroup("benchmarks", prefix_group_id=False) as benchmarks:
            benchmark_tasks = self._get_ripsaw().get_benchmarks()
            chain(*benchmark_tasks)
        install_cluster >> benchmarks >> cleanup_cluster

    def _get_openshift_installer(self):
        return openshift.OpenshiftInstaller(self.dag, self.version, self.platform, self.profile)

    def _get_ripsaw(self): 
        return ripsaw.Ripsaw(self.dag, self.version, self.platform, self.profile, self.metadata_args)




release_manifest = manifest.Manifest(root_dag_dir)
for release in release_manifest.get_releases():
    print(release)
    nightly = OpenshiftNightlyDAG(release['version'], release['platform'], release['profile'])
    nightly.build()
    globals()[nightly.release] = nightly.dag