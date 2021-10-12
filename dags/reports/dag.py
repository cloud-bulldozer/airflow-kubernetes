
from airflow import DAG
import os
import yaml
from datetime import datetime, timedelta
from reports.tasks import generate

# Base Directory where all DAG Code Lives
root_dag_dir = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))

with open(f"{root_dag_dir}/reports/config.yaml") as config_file:
    try:
        config = yaml.safe_load(config_file)
    except yaml.YAMLError as exc:
        print(exc)


default_args = {
    'owner': 'XYZ',
    'start_date': datetime(2020, 4, 1),
    'schedule_interval': '@daily',
}
dag = DAG('generate_reports', catchup=False, default_args=default_args)

generate_report_task = generate.get_task(dag, config)