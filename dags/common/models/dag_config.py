from dataclasses import dataclass, field
from typing import Optional
from datetime import timedelta, datetime
from common.util import slack_integration

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
            'on_failure_callback': slack_integration.task_fail_slack_alert,
            'retry_delay': timedelta(minutes=5)
        })
    executor_image: Optional[dict] = field(default_factory=lambda: {
            "repository": "quay.io/cloud-bulldozer",
            "tag": "2.6.2"
        })
    dependencies: Optional[dict] = field(default_factory=lambda: {})
