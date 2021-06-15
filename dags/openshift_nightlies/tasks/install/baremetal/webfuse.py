import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(dirname(abspath(dirname(__file__))))))
from util import var_loader, kubeconfig, constants

import json

from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable
from kubernetes.client import models as k8s

# Defines Tasks for installation of Openshift Clusters
class BaremetalWebfuseInstaller():
    def __init__(self, dag, version, release_stream, platform, profile, build):

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
        self.openshift_build = build

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="install", version=version, platform=platform, profile=profile)
       
        self.install_secrets = Variable.get(
            f"baremetal_openshift_install_config", deserialize_json=True)

    def get_deploy_app_task(self):
        return self._get_task()        

    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, trigger_rule="all_success"):
        bash_script = f"{constants.root_dag_dir}/scripts/install/baremetal_deploy_webfuse.sh"

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        config = {
            **self.vars,
            **self.install_secrets,
            **{ "es_server": var_loader.get_elastic_url() }
        }
        
        config['version'] = config['openshift_release']
        config['build'] = config['openshift_build']
        
        # Required Environment Variables for Install script
        env = {
            "SSHKEY_TOKEN": config['sshkey_token'],
            "ORCHESTRATION_HOST": config['provisioner_hostname'],
            "ORCHESTRATION_USER": config['provisioner_user'],
            "WEBFUSE_SKIPTAGS": config['webfuse_skiptags'],
            "WEBFUSE_PLAYBOOK": config['webfuse_playbook'],
            **self._insert_kube_env()
        }


        # Dump all vars to json file for Ansible to pick up
        with open(f"/tmp/{self.version}-{self.platform}-{self.profile}-task.json", 'w') as json_file:
            json.dump(config, json_file, sort_keys=True, indent=4)

        return BashOperator(
            task_id="deploy-webfuse",
            depends_on_past=False,
            bash_command=f"{bash_script} -p {self.platform} -v {self.version} -j /tmp/{self.version}-{self.platform}-{self.profile}-task.json -o deploy_app ",
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
