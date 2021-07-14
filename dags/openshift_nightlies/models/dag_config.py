import sys
from os.path import abspath, dirname
from dataclasses import dataclass, field
from typing import Optional
from datetime import timedelta, datetime

@dataclass
class DagConfig:
    schedule_interval: Optional[str] = None
    cleanup_on_success: Optional[bool] = True
    default_args: Optional[dict] = field(default_factory=lambda: {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': datetime(2021, 1, 1),
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 1,
            'retry_delay': timedelta(minutes=5)
        })
