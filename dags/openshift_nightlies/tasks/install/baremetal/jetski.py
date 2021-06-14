import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(dirname(abspath(dirname(__file__))))))
from util import var_loader, kubeconfig, constants
from tasks.install.baremetal import webfuse

import json

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class BaremetalOpenshiftInstaller():
    def __init__(self, dag, version, release_stream, platform, profile, version_alias):

        self.exec_config = {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/mukrishn/jetski:2.0",
                            image_pull_policy="Always",
                            volume_mounts=[
                                kubeconfig.get_empty_dir_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_empty_dir_volume_mount()]
                )
            )
        }

        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. 4.6/4.7, major.minor only
        self.openshift_release = release_stream # true release stream to follow. Nightlies, CI, etc. 
        self.profile = profile  # e.g. default/ovn
        self.openshift_build = version_alias

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="install", version=version, platform=platform, profile=profile)
       
        self.install_secrets = Variable.get(
            f"baremetal_openshift_install_config", deserialize_json=True)

    def get_install_task(self):
        webfuse_installer = self._get_webfuse_installer()
        install_cluster = self._get_task(operation="install")
        deploy_webfuse = webfuse_installer.get_deploy_app_task()

        install_cluster >> deploy_webfuse

        return install_cluster

    def get_scaleup_task(self):
        return self._get_task(operation="scaleup")

    def _get_webfuse_installer(self):
        return webfuse.BaremetalWebfuseInstaller(self.dag, self.version, self.openshift_release, self.platform, self.profile, self.openshift_build)

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        bash_script = ""

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        config = {
            **self.vars,
            **self.install_secrets,
            **{ "es_server": var_loader.get_elastic_url() }
        }
        
        config['pullsecret'] = json.dumps(config['openshift_install_pull_secret'])
        config['version'] = config['openshift_release']
        config['build'] = config['openshift_build']
        
        # Required Environment Variables for Install script
        env = {
            "SSHKEY_TOKEN": config['sshkey_token'],
            "OPENSHIFT_WORKER_COUNT": config['openshift_worker_count'],
            "BAREMETAL_NETWORK_CIDR": config['baremetal_network_cidr'],
            "BAREMETAL_NETWORK_VLAN": config['baremetal_network_vlan'],
            "OPENSHIFT_BASE_DOMAIN": config['openshift_base_domain'],
            "KUBECONFIG_PATH": config['kubeconfig_path'],
            **self._insert_kube_env()
        }

        if operation == "install":
            config['worker_count'] = config['openshift_worker_count']
            bash_script = f"{constants.root_dag_dir}/scripts/install/baremetal_install.sh"
        else:
            config['worker_count'] = config['openshift_worker_scaleup_target']
            bash_script = f"{constants.root_dag_dir}/scripts/install/baremetal_scaleup.sh"

        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json", 'w') as json_file:
            json.dump(config, json_file, sort_keys=True, indent=4)

        return BashOperator(
            task_id=f"{operation}-cluster",
            depends_on_past=False,
            bash_command=f"{bash_script} -p {self.platform} -v {self.version} -j /tmp/{self.version}-{self.platform}-{self.profile}-{operation}-task.json -o {operation} ",
            retries=3,
            dag=self.dag,
            trigger_rule=trigger_rule,
            executor_config=self.exec_config,
            env=env
        )

    # This Helper Injects Airflow environment variables into the task execution runtime
    # This allows the task to interface with the Kubernetes cluster Airflow is hosted on.
    def _insert_kube_env(self):
        return {key: value for (key, value) in environ.items() if "KUBERNETES" in key}
