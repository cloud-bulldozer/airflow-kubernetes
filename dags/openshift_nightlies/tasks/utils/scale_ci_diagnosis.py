import sys
from os.path import abspath, dirname
from os import environ

sys.path.insert(0, dirname(dirname(abspath(dirname(__file__)))))
from util import var_loader, kubeconfig, constants
from tasks.index.status import StatusIndexer

import json
from datetime import timedelta
from airflow.operators.bash_operator import BashOperator
from airflow.operators.subdag_operator import SubDagOperator
from airflow.models import Variable
from airflow.models import DAG
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s




class Diagnosis():
    def __init__(self, dag, version, release_stream, latest_release, platform, profile, default_args):

        self.exec_config = {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image="quay.io/keithwhitley4/airflow-ansible:2.1.0",
                            image_pull_policy="Always",
                            env=[
                                kubeconfig.get_kubeadmin_password(
                        version, platform, profile)
                            ],
                            volume_mounts=[
                                kubeconfig.get_kubeconfig_volume_mount()]

                        )
                    ],
                    volumes=[kubeconfig.get_kubeconfig_volume(
                        version, platform, profile)]
                )
            )
        }

        # General DAG Configuration
        self.dag = dag
        self.platform = platform  # e.g. aws
        self.version = version  # e.g. stable/.next/.future
        self.release_stream = release_stream
        self.latest_release = latest_release # latest relase from the release stream
        self.profile = profile  # e.g. default/ovn
        self.default_args = default_args

        # Airflow Variables
        self.SNAPPY_DATA_SERVER_URL = Variable.get("SNAPPY_DATA_SERVER_URL")
        self.SNAPPY_DATA_SERVER_USERNAME = Variable.get("SNAPPY_DATA_SERVER_USERNAME")
        self.SNAPPY_DATA_SERVER_PASSWORD = Variable.get("SNAPPY_DATA_SERVER_PASSWORD")

        # Specific Task Configuration
        self.vars = var_loader.build_task_vars(
            task="utils", version=version, platform=platform, profile=profile)
        self.git_name=self._git_name()
        self.env = {
            "OPENSHIFT_CLIENT_LOCATION": self.latest_release["openshift_client_location"],
            "SNAPPY_DATA_SERVER_URL": self.SNAPPY_DATA_SERVER_URL,
            "SNAPPY_DATA_SERVER_USERNAME": self.SNAPPY_DATA_SERVER_USERNAME,
            "SNAPPY_DATA_SERVER_PASSWORD": self.SNAPPY_DATA_SERVER_PASSWORD,
            "SNAPPY_USER_FOLDER": self.git_name

        }


    def _git_name(self):
        git_username = var_loader.get_git_user()
        if git_username == 'cloud-bulldozer':
            return f"perf-ci"
        else: 
            return f"{git_username}"

    def get_utils(self):
        utils = self._get_utils(self.vars["utils"])
        return utils

    def _get_utils(self,utils):
        for index, util in enumerate(utils):
            utils[index] = self._get_util(util)
        return utils 

    def _get_util(self, util):
        env = {**self.env, **util.get('env', {}), **{"ES_SERVER": var_loader.get_elastic_url()}, **{"KUBEADMIN_PASSWORD": environ.get("KUBEADMIN_PASSWORD", "")}}
        return BashOperator(
            task_id=f"{util['name']}",
            depends_on_past=False,
            bash_command=f"{constants.root_dag_dir}/scripts/utils/run_scale_ci_diagnosis.sh -w {util['workload']} -c {util['command']} ",
            retries=3,
            dag=self.dag,
            env=env,
            executor_config=self.exec_config
        )


