import sys
import os
import logging
from airflow import DAG
from airflow.models.baseoperator import chain
from airflow.utils.task_group import TaskGroup
from airflow.config_templates.airflow_local_settings import LOG_FORMAT
from airflow.models.param import Param

# Configure Path to have the Python Module on it
from common.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.tasks.install.cloud import openshift
from openshift_nightlies.tasks.install.openstack import jetpack
from openshift_nightlies.tasks.install.baremetal import jetski, webfuse
from openshift_nightlies.tasks.install.rosa import rosa
from openshift_nightlies.tasks.install.rosahcp import rosahcp
from openshift_nightlies.tasks.install.rogcp import rogcp
from openshift_nightlies.tasks.install.hypershift import hypershift
from openshift_nightlies.tasks.install.prebuilt import initialize_cluster
from openshift_nightlies.tasks.benchmarks import e2e
from openshift_nightlies.tasks.utils import rosa_post_install, scale_ci_diagnosis, final_dag_status
from openshift_nightlies.util import constants, manifest
from abc import ABC, abstractmethod

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

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
        self.tags = [self.release.platform, self.release.release_stream, self.release.variant,
                     self.release.version_alias, self.release._generate_cluster_name()]

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

    def _get_rosa_postinstall_setup(self):
        return rosa_post_install.Diagnosis(self.dag, self.config, self.release)


class CloudOpenshiftNightlyDAG(AbstractOpenshiftNightlyDAG):

    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        final_status=final_dag_status.get_task(self.dag)

        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            must_gather = self._get_scale_ci_diagnosis().get_must_gather("must-gather")
            chain(*benchmark_tasks)
            # Configure must_gather as downstream of all benchmark tasks
            for benchmark in benchmark_tasks:
                benchmark >> must_gather

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> benchmarks >> final_status

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
        install_cluster >> benchmark_stg_1
        install_cluster >> scaleup_cluster >> benchmark_stg_2
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
        final_status=final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)

        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> benchmarks

    def _get_openshift_installer(self):
        return jetpack.OpenstackJetpackInstaller(self.dag, self.config, self.release)


class RosaNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        final_status = final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            must_gather = self._get_scale_ci_diagnosis().get_must_gather("must-gather")
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
            # Configure must_gather as downstream of all benchmark tasks
            for benchmark in benchmark_tasks:
                benchmark >> must_gather
        rosa_post_installation = self._get_rosa_postinstall_setup()._get_rosa_postinstallation()
        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> rosa_post_installation >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> rosa_post_installation >> benchmarks >> final_status

    def _get_openshift_installer(self):
        return rosa.RosaInstaller(self.dag, self.config, self.release)

    def _get_e2e_benchmarks(self, task_group="benchmarks"):
        return e2e.E2EBenchmarks(self.dag, self.config, self.release, task_group)

class RosaHCPNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_hcp_task()
        wait_task = installer.wait_task()
        wait_before_cleanup = installer.wait_task(id="wait_before_cleanup")
        for c_id, install_hc, postinstall_hc, cleanup_hc in install_cluster:
            benchmark = self._add_benchmarks(task_group=c_id)
            install_hc >> postinstall_hc >> wait_task >> benchmark >> wait_before_cleanup >> cleanup_hc

    def _get_openshift_installer(self):
        return rosahcp.RosaHCPInstaller(self.dag, self.config, self.release)

    def _get_e2e_benchmarks(self, task_group="benchmarks"):
        return e2e.E2EBenchmarks(self.dag, self.config, self.release, task_group)

    def _add_benchmarks(self, task_group):
        with TaskGroup(task_group, prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks(task_group).get_benchmarks()
            chain(*benchmark_tasks)
        return benchmarks


class RoGCPNightlyDAG(AbstractOpenshiftNightlyDAG):
    def build(self):
        installer = self._get_openshift_installer()
        install_cluster = installer.get_install_task()
        final_status = final_dag_status.get_task(self.dag)
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            must_gather = self._get_scale_ci_diagnosis().get_must_gather("must-gather")
            chain(*benchmark_tasks)
            # Configure must_gather as downstream of all benchmark tasks
            for benchmark in benchmark_tasks:
                benchmark >> must_gather
        if self.config.cleanup_on_success:
            cleanup_cluster = installer.get_cleanup_task()
            install_cluster >> benchmarks >> cleanup_cluster >> final_status
        else:
            install_cluster >> benchmarks >> final_status

    def _get_openshift_installer(self):
        return rogcp.RoGCPInstaller(self.dag, self.config, self.release)


class HypershiftNightlyDAG(AbstractOpenshiftNightlyDAG):

    def build(self):
        mgmt_installer = self._get_openshift_installer()
        hosted_installer = self._get_hypershift_openshift_installer()
        install_mgmt_cluster = mgmt_installer.get_install_task()
        rosa_post_installation = self._get_rosa_postinstall_setup()._get_rosa_postinstallation()
        wait_task = hosted_installer.wait_task()
        wait_before_cleanup = hosted_installer.wait_task(id="wait_before_cleanup")
        if self.config.cleanup_on_success:
            cleanup_mgmt_cluster = mgmt_installer.get_cleanup_task()
            cleanup_hosted_cluster = hosted_installer.get_hosted_cleanup_task()
            cleanup_operator = hosted_installer.get_operator_cleanup_task()
            for c_id, install_hc, cleanup_hc in cleanup_hosted_cluster:
                benchmark = self._add_benchmarks(task_group=c_id)
                install_mgmt_cluster >> rosa_post_installation >> install_hc >> wait_task >> benchmark
                benchmark >> wait_before_cleanup >> cleanup_hc >> cleanup_operator >> cleanup_mgmt_cluster
        else:
            install_hosted_cluster = hosted_installer.get_hosted_install_task()
            for c_id, install_hc in install_hosted_cluster:
                benchmark = self._add_benchmarks(task_group=c_id)
                install_mgmt_cluster >> rosa_post_installation >> install_hc >> wait_task >> benchmark

    def _get_openshift_installer(self):
        return rosahcp.RosaHCPInstaller(self.dag, self.config, self.release)

    def _get_hypershift_openshift_installer(self):
        return hypershift.HypershiftInstaller(self.dag, self.config, self.release)

    def _get_e2e_benchmarks(self, task_group):
        return e2e.E2EBenchmarks(self.dag, self.config, self.release, task_group)

    def _add_benchmarks(self, task_group):
        with TaskGroup(task_group, prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = self._get_e2e_benchmarks(task_group).get_benchmarks()
            chain(*benchmark_tasks)
        return benchmarks


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
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            must_gather = self._get_scale_ci_diagnosis().get_must_gather("must-gather")
            benchmark_tasks = self._get_e2e_benchmarks().get_benchmarks()
            chain(*benchmark_tasks)
            for benchmark in benchmark_tasks:
                benchmark >> must_gather
        initialize_cluster >> benchmarks

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
        elif openshift_release.platform == "rosahcp":
            nightly = RosaHCPNightlyDAG(openshift_release, dag_config)            
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
