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
from common.models.dag_config import DagConfig
from nocp.util import manifest, constants
from nocp.tasks.benchmarks import nocp
from abc import ABC, abstractmethod

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task")
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter(LOG_FORMAT)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
log.addHandler(handler)


class NocpDAG(ABC):
    def __init__(self, app, config: DagConfig):
        self.config = config
        # app name: Later modules use this to invoke app specific code
        self.app = app

        self.dag = DAG(
            app,
            default_args=self.config.default_args,
            description=f"DAG for Non Openshift workload {app}",
            schedule_interval=self.config.schedule_interval,
            max_active_runs=1,
            catchup=False
        )

        super().__init__()

    def build(self):
        with TaskGroup("benchmarks", prefix_group_id=False, dag=self.dag) as benchmarks:
            benchmark_tasks = nocp.NOCPBenchmarks(
                self.app, self.dag, self.config).get_benchmarks()
            chain(*benchmark_tasks)

        benchmarks


def run_nocp_dags():
    nocp_manifest = manifest.Manifest(constants.root_dag_dir)
    for app_config in nocp_manifest.get_nocp_configs():
        app = app_config["app"]
        dag_config = app_config["config"]
        nightly = NocpDAG(app, dag_config)

        nightly.build()
        globals()[nightly.app] = nightly.dag


run_nocp_dags()
