
from airflow import DAG
import os
import yaml
import sys
import logging
from datetime import datetime, timedelta
from reports.tasks import generate
from airflow.config_templates.airflow_local_settings import LOG_FORMAT

# Base Directory where all DAG Code Lives
root_dag_dir = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))

# Set Task Logger to INFO for better task logs
log = logging.getLogger("airflow.task")
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter(LOG_FORMAT)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
log.addHandler(handler)

with open(f"{root_dag_dir}/reports/config.yaml") as config_file:
    try:
        config = yaml.safe_load(config_file)
    except yaml.YAMLError as exc:
        print(exc)


default_args = {
    'owner': 'airflow',
    'start_date': datetime(2020, 4, 1),
    'schedule_interval': '@hourly',
}
dag = DAG('generate_reports', catchup=False, default_args=default_args)

generate_report_task = generate.get_task(dag, config)