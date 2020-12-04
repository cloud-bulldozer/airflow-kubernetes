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
from util import var_loader, manifest

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task.operators")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
log.addHandler(handler)

class OpenshiftNightlyDAG():
    def __init__(self, platform, version, profile):
        self.platform = platform
        self.version = version
        self.profile = profile
        self.release = f"{self.version}_{self.platform}_{self.profile}"
        self.metadata_args = {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': days_ago(2),
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
        uperf = ripsaw.get_task(self.dag, self.platform, self.version, operation="uperf")
        http = ripsaw.get_task(self.dag, self.platform, self.version, operation="http")
        http_copy = ripsaw.get_task(self.dag, self.platform, self.version, operation="http_post")
        scale_up = ripsaw.get_task(self.dag, self.platform, self.version, operation="scale_up")
        scale_down = ripsaw.get_task(self.dag, self.platform, self.version, operation="scale_down")
        cluster_density = ripsaw.get_task(self.dag, self.platform, self.version, "cluster_density")
        kubelet_density = ripsaw.get_task(self.dag, self.platform, self.version, "kubelet_density") 

        install_cluster >> [http, uperf] >> scale_up >> [http_copy, cluster_density, kubelet_density] >> scale_down >> cleanup_cluster


    def _get_openshift_installer(self):
        return openshift.OpenshiftInstaller(self.dag, self.platform, self.version, self.profile)

    def _get_benchmarks(self): 
        pass




release_manifest = manifest.Manifest(root_dag_dir)
for release in release_manifest.get_releases():
    nightly = OpenshiftNightlyDAG(release['platform'], release['version'], release['profile'])
    nightly.build()
    globals()[nightly.release] = nightly.dag