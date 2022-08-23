import yaml
import requests
from common.models.dag_config import DagConfig

class Manifest():

    def __init__(self, root_dag_dir):
        with open(f"{root_dag_dir}/manifest.yaml") as manifest_file:
            try:
                self.yaml = yaml.safe_load(manifest_file)
            except yaml.YAMLError as exc:
                print(exc)
        self.nocp_configs = []

    # Returns app name (example, ocm) and schedule as part of config
    def get_nocp_configs(self):
        for app,schedule in self.yaml['dagConfig']['schedules']['nocp'].items():
            if schedule == 'None':
                schedule = None
            dag_config = self._build_dag_config(schedule)
            self.nocp_configs.append(
                {
                    "config": dag_config,
                    "app": app
                }
            )
        return self.nocp_configs

    def _build_dag_config(self, schedule_interval):
        return DagConfig(
            schedule_interval=schedule_interval,
            executor_image=self.yaml['dagConfig'].get('executorImages', None)
        )
