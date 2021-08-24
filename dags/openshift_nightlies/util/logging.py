import sys
from copy import deepcopy

from airflow.config_templates.airflow_local_settings import DEFAULT_LOGGING_CONFIG

LOGGING_CONFIG = deepcopy(DEFAULT_LOGGING_CONFIG)

LOGGING_CONFIG["handlers"]["custom_console"] = {
    "class": "logging.StreamHandler",
    "formatter": "airflow",
    "stream": sys.__stdout__,
}
LOGGING_CONFIG["loggers"]["airflow.task"]["handlers"].append("custom_console")