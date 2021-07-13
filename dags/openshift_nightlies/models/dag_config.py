from dataclasses import dataclass
from typing import Optional
from datetime import timedelta, datetime

@dataclass
class DagConfig:
    schedule_interval: Optional[str] = None
    default_args: Optional[dict] = {
            'owner': 'airflow',
            'depends_on_past': False,
            'start_date': datetime(2021, 1, 1),
            'email': ['airflow@example.com'],
            'email_on_failure': False,
            'email_on_retry': False,
            'retries': 1,
            'retry_delay': timedelta(minutes=5)
        }
