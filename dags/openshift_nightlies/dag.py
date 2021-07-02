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
from tasks.install.cloud import openshift
from tasks.install.openstack import jetpack
from tasks.install.baremetal import jetski
from tasks.benchmarks import e2e
from tasks.utils import scale_ci_diagnosis
from tasks.index import status
from util import var_loader, manifest, constants
from abc import ABC, abstractmethod

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task.operators")
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
log.addHandler(handler)

# This Applies to all DAGs
class AbstractOpenshiftNightlyDAG(ABC):
    def __init__(self, version, release_stream, platform, profile, version_alias, schedule_interval=None):
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
        tags = []
        tags.append(self.platform)
        tags.append(self.release_stream)
        tags.append(self.profile)
        tags.append(self.version_alias)

        if schedule_interval is None:
            schedule_interval='0 12 * * 1,3,5'

        self.dag = DAG(
            self.release,
            default_args=self.metadata_args,
            tags=tags,
            description=f"DAG for Openshift Nightly builds {self.release}",
            schedule_interval=schedule_interval,
            max_active_runs=1,
            catchup=False
        )

        super().__init__()

    @abstractmethod
    def build(self):
        raise NotImplementedError()

    @abstractmethod
    def _get_openshift_installer(self):
        raise NotImplementedError()

    def _get_e2e_benchmarks(self): 
        return e2e.E2EBenchmarks(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile, self.metadata_args)

    def _get_scale_ci_diagnosis(self):
        return scale_ci_diagnosis.Diagnosis(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile, self.metadata_args)


class CloudOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def __init__(self, version, release_stream, platform, profile, version_alias):
        super().__init__(version, release_stream, platform, profile, version_alias)
        self.release_stream_base_url = Variable.get("release_stream_base_url")
        self.latest_release = var_loader.get_latest_release_from_stream(self.release_stream_base_url, self.release_stream)
    
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        cleanup_cluster = installer.get_cleanup_task()
        with TaskGroup("utils", prefix_group_id=False, dag=self.dag) as utils:
            utils_tasks=self._get_scale_ci_diagnosis().get_utils()
            chain(*utils_tasks)
            utils_tasks[-1] >> cleanup_cluster
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
            benchmark_tasks[-1] >> utils

        install_cluster >> benchmarks

    def _get_openshift_installer(self):
        return openshift.CloudOpenshiftInstaller(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile)



class BaremetalOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def __init__(self, version, release_stream, platform, profile, version_alias, build):
        super().__init__(version, release_stream, platform, profile, version_alias)
        self.openshift_build = build
        
    def build(self):
        bm_installer = self._get_openshift_installer()
        install_cluster = bm_installer.get_install_task()
        scaleup_cluster = bm_installer.get_scaleup_task()
        install_cluster >> scaleup_cluster

    def _get_openshift_installer(self):
        return jetski.BaremetalOpenshiftInstaller(self.dag, self.version, self.release_stream, self.platform, self.profile, self.openshift_build)



class OpenstackNightlyDAG(AbstractOpenshiftNightlyDAG):
    def __init__(self, version, release_stream, platform, profile, version_alias):
        schedule_interval = '0 12 * * 1-6'
        super().__init__(version, release_stream, platform, profile, version_alias, schedule_interval)
        self.release_stream_base_url = Variable.get("release_stream_base_url")
        self.latest_release = var_loader.get_latest_release_from_stream(self.release_stream_base_url, self.release_stream)

    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        cleanup_cluster = installer.get_cleanup_task()
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
            benchmark_tasks[-1] >> cleanup_cluster

        install_cluster >> benchmarks

    def _get_openshift_installer(self):
        return jetpack.OpenstackJetpackInstaller(self.dag, self.version, self.release_stream, self.latest_release, self.platform, self.profile)



release_manifest = manifest.Manifest(constants.root_dag_dir)
for release in release_manifest.get_releases():
    nightly = None
    if release['platform'] == "baremetal":
        nightly = BaremetalOpenshiftNightlyDAG(release['version'], release['releaseStream'], release['platform'], release['profile'], release.get('versionAlias', 'none'), release['build'])
    elif release['platform'] == "openstack":
        nightly = OpenstackNightlyDAG(release['version'], release['releaseStream'], release['platform'], release['profile'], release.get('versionAlias', 'none'))
    else:
        nightly = CloudOpenshiftNightlyDAG(release['version'], release['releaseStream'], release['platform'], release['profile'], release.get('versionAlias', 'none'))
    
    nightly.build()
    globals()[nightly.release] = nightly.dag