import sys
import os
import logging 
import json
from datetime import timedelta
from airflow import DAG
from airflow.utils.dates import days_ago
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

class OpenshiftNightlyDAG():
    def __init__(self, version, release_stream, platform, profile, tags):
        self.platform = platform
        self.version = version
        self.release_stream = release_stream
        self.profile = profile
        self.release = f"{self.version}_{self.platform}_{self.profile}"
        self.metadata_args = {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': days_ago(3),
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 1,
            'release': self.release,
            'retry_delay': timedelta(minutes=5),
        }

        tags.append(self.platform)
        tags.append(self.release_stream)

        self.dag = DAG(
            self.release,
            default_args=self.metadata_args,
            tags=tags,
            description=f"DAG for Openshift Nightly builds {self.release}",
            schedule_interval=timedelta(days=3),
        )
    
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        cleanup_cluster = installer.get_cleanup_task()
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)

        with TaskGroup("Index Results", prefix_group_id=False, dag=self.dag) as post_steps: 
            index_status_task = self._get_status_indexer().get_index_task()

        install_cluster >> benchmarks >> [post_steps, cleanup_cluster]

    def _get_openshift_installer(self):
        return openshift.OpenshiftInstaller(self.dag, self.version, self.release_stream, self.platform, self.profile)

    def _get_e2e_benchmarks(self): 
        return e2e.E2EBenchmarks(self.dag, self.version, self.release_stream, self.platform, self.profile, self.metadata_args)

    def _get_status_indexer(self):
        return status.StatusIndexer(self.dag, self.version, self.release_stream, self.platform, self.profile)



release_manifest = manifest.Manifest(constants.root_dag_dir)
for release in release_manifest.get_releases():
    print(release)
    nightly = OpenshiftNightlyDAG(release['version'], release['releaseStream'], release['platform'], release['profile'], release.get('tags', []))
    nightly.build()
    globals()[nightly.release] = nightly.dag