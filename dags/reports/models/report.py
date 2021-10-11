from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime

@dataclass
class Report:
    cluster_name: str
    openshift_version: str
    openshift_platform: str
    openshift_version: str
    report_type: str
    metadata: dict
    results: dict
    metrics: dict
    links: dict
    timestamp: datetime 