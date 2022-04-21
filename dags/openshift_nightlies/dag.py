import sys
import os
import logging
import json
from datetime import timedelta, datetime
from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.models import Variable
from airflow.models.baseoperator import chain
from airflow.operators.bash import BashOperator
from airflow.utils.task_group import TaskGroup
from airflow.config_templates.airflow_local_settings import LOG_FORMAT
from airflow.models.param import Param

# Configure Path to have the Python Module on it
sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from openshift_nightlies.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease, BaremetalRelease
from openshift_nightlies.tasks.install.cloud import openshift
from openshift_nightlies.tasks.install.openstack import jetpack
from openshift_nightlies.tasks.install.baremetal import jetski, webfuse
from openshift_nightlies.tasks.install.rosa import rosa
from openshift_nightlies.tasks.install.rogcp import rogcp
from openshift_nightlies.tasks.install.hypershift import hypershift
from openshift_nightlies.tasks.install.prebuilt import initialize_cluster
from openshift_nightlies.tasks.benchmarks import e2e
from openshift_nightlies.tasks.utils import rosa_post_install, scale_ci_diagnosis, platform_connector,final_dag_status
from openshift_nightlies.tasks.index import status
from openshift_nightlies.util import var_loader, manifest, constants
from abc import ABC, abstractmethod

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task")
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter(LOG_FORMAT)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
log.addHandler(handler)


# This Applies to all DAGs


class AbstractOpenshiftNightlyDAG(ABC):
    def __init__(self, release: OpenshiftRelease, config: DagConfig):
        self.release = release
        self.config = config
        self.release_name = release.get_release_name()

        self.tags = []
        self.tags.append(self.release.platform)
        self.tags.append(self.release.release_stream)
        self.tags.append(self.release.variant)
        self.tags.append(self.release.version_alias)
        self.tags.append(self.release._generate_cluster_name())

        self.dag = DAG(
            self.release_name,
            default_args=self.config.default_args,
            tags=self.tags,
            description=f"DAG for Openshift Nightly builds {self.release_name}",
            schedule_interval=self.config.schedule_interval,
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
        return e2e.E2EBenchmarks(self.dag, self.config, self.release)

    def _get_scale_ci_diagnosis(self):
        return scale_ci_diagnosis.Diagnosis(self.dag, self.config, self.release)

    def _get_platform_connector(self):
        return platform_connector.PlatformConnectorTask(self.dag, self.config, self.release)

    def _get_rosa_postinstall_setup(self, task_group=""):
        return rosa_post_install.Diagnosis(self.dag, self.config, self.release, task_group=task_group)


class CloudOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        connect_to_platform = self._get_platform_connector().get_task()
        final_status=final_dag_status.get_task(self.dag)

        with TaskGroup("utils", prefix_group_id=False, dag=self.dag) as utils:
            utils_tasks = self._get_scale_ci_diagnosis().get_utils()
            chain(*utils_tasks)

        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> connect_to_platform >> benchmarks >> utils >> cleanup_cluster >> final_status
        else:
            install_cluster >> connect_to_platform >> benchmarks >> utils

    def _get_openshift_installer(self):
        return openshift.CloudOpenshiftInstaller(self.dag, self.config, self.release)


class BaremetalOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        bm_installer = self._get_openshift_installer()
        webfuse_installer = self._get_webfuse_installer()

        install_cluster = bm_installer.get_install_task()
        benchmark_stg_1 = self._add_benchmarks(task_group="install-bench")

        deploy_webfuse = webfuse_installer.get_deploy_app_task()
        benchmark_stg_2 = self._add_benchmarks(task_group="scaleup-bench")

        scaleup_cluster = bm_installer.get_scaleup_task()
        benchmark_stg_3 = self._add_benchmarks(task_group="webfuse-bench")
        connect_to_platform = self._get_platform_connector().get_task()
        install_cluster >> connect_to_platform
        connect_to_platform >> benchmark_stg_1 
        connect_to_platform >> scaleup_cluster >> benchmark_stg_2 
        scaleup_cluster >> deploy_webfuse >> benchmark_stg_3

    def _get_openshift_installer(self):
        return jetski.BaremetalOpenshiftInstaller(self.dag, self.config, self.release)

    def _get_webfuse_installer(self):
        return webfuse.BaremetalWebfuseInstaller(self.dag, self.config, self.release)

    def _get_e2e_benchmarks(self, task_group):
        return e2e.E2EBenchmarks(self.dag, self.config, self.release, task_group)

    def _add_benchmarks(self, task_group):
        with TaskGroup(task_group, prefix_group_id=True, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks(task_group).get_benchmarks()
            chain(*benchmark_tasks)
        return benchmarks

class OpenstackNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        connect_to_platform = self._get_platform_connector().get_task()
        final_status=final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> connect_to_platform >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> connect_to_platform >> benchmarks

    def _get_openshift_installer(self):
        return jetpack.OpenstackJetpackInstaller(self.dag, self.config, self.release)


class RosaNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        connect_to_platform = self._get_platform_connector().get_task()
        final_status=final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
        
        rosa_post_installation = self._get_rosa_postinstall_setup()._get_rosa_postinstallation()

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> rosa_post_installation >> connect_to_platform >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> rosa_post_installation >> connect_to_platform >> benchmarks

    def _get_openshift_installer(self):
        return rosa.RosaInstaller(self.dag, self.config, self.release)


class RoGCPNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        connect_to_platform = self._get_platform_connector().get_task()
        final_status=final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
        

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> connect_to_platform >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> connect_to_platform >> benchmarks

    def _get_openshift_installer(self):
        return rogcp.RoGCPInstaller(self.dag, self.config, self.release)

class HypershiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        mgmt_installer = self._get_openshift_installer()
        hosted_installer = self._get_hypershift_openshift_installer()
        install_mgmt_cluster = mgmt_installer.get_install_task()
        connect_to_platform = self._get_platform_connector().get_task()

        rosa_post_installation = self._get_rosa_postinstall_setup()._get_rosa_postinstallation()

        if self.config.cleanup_on_success:
            install_hosted_cluster = hosted_installer.get_hosted_install_task()
            cleanup_mgmt_cluster = mgmt_installer.get_cleanup_task()
            cleanup_hosted_cluster = hosted_installer.get_cleanup_task()
            for c_id, install_hc in install_hosted_cluster:
                benchmark = self._add_benchmarks(task_group=c_id)
                hc_post_installation = self._get_rosa_postinstall_setup(task_group=c_id)._get_rosa_postinstallation()
                hc_connect_to_platform = self._get_hc_platform_connector(task_group=c_id).get_task()            
                install_mgmt_cluster >> rosa_post_installation >> connect_to_platform
                connect_to_platform >> install_hc >> hc_post_installation >> [hc_connect_to_platform, benchmark]
                [hc_connect_to_platform, benchmark] >> cleanup_hosted_cluster >> cleanup_mgmt_cluster
        else:
            install_hosted_cluster = hosted_installer.get_hosted_install_task()
            for c_id, install_hc in install_hosted_cluster:
                benchmark = self._add_benchmarks(task_group=c_id)
                hc_post_installation = self._get_rosa_postinstall_setup(task_group=c_id)._get_rosa_postinstallation()
                hc_connect_to_platform = self._get_hc_platform_connector(task_group=c_id).get_task()            
                install_mgmt_cluster >> rosa_post_installation >> connect_to_platform
                connect_to_platform >> install_hc >> hc_post_installation >> hc_connect_to_platform >> benchmark

    def _get_openshift_installer(self):
        return rosa.RosaInstaller(self.dag, self.config, self.release)

    def _get_hypershift_openshift_installer(self):
        return hypershift.HypershiftInstaller(self.dag, self.config, self.release)

    def _get_e2e_benchmarks(self, task_group):
        return e2e.E2EBenchmarks(self.dag, self.config, self.release, task_group)

    def _add_benchmarks(self, task_group):
        with TaskGroup(task_group, prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks(task_group).get_benchmarks()
            chain(*benchmark_tasks)
        return benchmarks

    def _get_hc_platform_connector(self, task_group):
        return platform_connector.PlatformConnectorTask(self.dag, self.config, self.release, task_group=task_group)

class PrebuiltOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):
    def __init__(self, Release: OpenshiftRelease, Config: DagConfig):
        AbstractOpenshiftNightlyDAG.__init__(self, release=Release, config=Config)

        self.dag = DAG(
            self.release_name,
            default_args=self.config.default_args,
            tags=self.tags,
            description=f"DAG for Prebuilt Openshift Nightly builds {self.release_name}",
            schedule_interval=self.config.schedule_interval,
            max_active_runs=1,
            catchup=False,
            params={
                'KUBEUSER': Param('<Enter openshift cluster-admin username>'),
                'KUBEPASSWORD': Param('<Enter openshift cluster password>'),
                'KUBEURL': Param('<Enter cluster URL>')
            }
        )
    
    def build(self):       

        installer = self._get_openshift_installer()
        initialize_cluster = installer.initialize_cluster_task()
        connect_to_platform = self._get_platform_connector().get_task()

        with TaskGroup("utils", prefix_group_id=False, dag=self.dag) as utils:
            utils_tasks = self._get_scale_ci_diagnosis().get_utils()
            chain(*utils_tasks)

        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)

        initialize_cluster >> connect_to_platform >> benchmarks >> utils
        
    def _get_openshift_installer(self):
        return initialize_cluster.InitializePrebuiltCluster(self.dag, self.config, self.release)

def build_releases():
    release_manifest = manifest.Manifest(constants.root_dag_dir)
    log.info(f"Latest Releases Found: {release_manifest.latest_releases}")
    for release in release_manifest.get_releases():
        openshift_release = release["release"]
        dag_config = release["config"]
        nightly = None
        if openshift_release.platform == "baremetal":
            nightly = BaremetalOpenshiftNightlyDAG(openshift_release, dag_config)
        elif openshift_release.platform == "openstack":
            nightly = OpenstackNightlyDAG(openshift_release, dag_config)
        elif openshift_release.platform == "rosa":
            nightly = RosaNightlyDAG(openshift_release, dag_config)
        elif openshift_release.platform == "rogcp":
            nightly = RoGCPNightlyDAG(openshift_release, dag_config)
        elif openshift_release.platform == "hypershift":
            nightly = HypershiftNightlyDAG(openshift_release, dag_config)
        elif openshift_release.platform == "prebuilt":
            nightly = PrebuiltOpenshiftNightlyDAG(openshift_release, dag_config)
        else:
            nightly = CloudOpenshiftNightlyDAG(openshift_release, dag_config)

        nightly.build()
        globals()[nightly.release_name] = nightly.dag


build_releases()
