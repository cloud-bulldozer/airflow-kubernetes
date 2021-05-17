import sys
import os
import logging 
import json
from datetime import timedelta, datetime
from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.models import Variable
from airflow.utils.helpers import chain
from airflow.operators.bash_operator import BashOperator
from airflow.utils.task_group import TaskGroup

# Configure Path to have the Python Module on it
sys.path.insert(0,os.path.abspath(os.path.dirname(__file__)))
from tasks.install import openshift
from tasks.benchmarks import e2e
from tasks.index import status
from util import var_loader, manifest, constants

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task.operators")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
log.addHandler(handler)

class BaremetalOpenshiftDAG():
    def __init__(self, version, release_stream, platform, profile, version_alias, tags):
        self.platform = platform
        self.version = version
        self.release_stream = release_stream
        self.profile = profile
        self.version_alias = version_alias
        self.release = f"{self.version}_{self.platform}_{self.profile}"
        self.metadata_args = {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': datetime(2021, 1, 1),
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 1,
            'release': self.release,
            'retry_delay': timedelta(minutes=5),
        }

        tags.append(self.platform)
        tags.append(self.release_stream)
        tags.append(self.profile)
        tags.append(self.version_alias)

        # self.release_stream_base_url = Variable.get("release_stream_base_url")
        # self.latest_release = var_loader.get_latest_release_from_stream(self.release_stream_base_url, self.release_stream)

        self.dag = DAG(
            self.release,
            default_args=self.metadata_args,
            tags=tags,
            description=f"DAG for Openshift builds {self.release}",
            schedule_interval='@daily',
            max_active_runs=1,
            catchup=False
        )
    
    def build(self):
        installer = self._get_openshift_installer()
        installer.get_install_task()

        # with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
        #     benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
        #     chain(*benchmark_tasks)
        #     benchmark_tasks[-1] >> cleanup_cluster

        # install_cluster >> scaleup_cluster

    def _get_openshift_installer(self):
        return openshift.OpenshiftInstaller(self.dag, self.version, self.release_stream, self.platform, self.profile, self.version_alias)

    # def _get_e2e_benchmarks(self): 
    #     return e2e.E2EBenchmarks(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile, self.metadata_args)



release_manifest = manifest.Manifest(constants.root_dag_dir)
for release in release_manifest.get_releases():
    print(release)
    baremetal = BaremetalOpenshiftDAG(release['version'], release['releaseStream'], release['platform'], release['profile'], release.get('versionAlias', 'none'), release.get('tags', []))
    baremetal.build()
    globals()[baremetal.release] = baremetal.dag