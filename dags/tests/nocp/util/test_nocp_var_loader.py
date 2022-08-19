from airflow.models import Variable
from nocp.util import var_loader
from os import environ
from unittest import mock

class TestVarLoader():

    def test_build_nocp_task_vars(self, test_config_dir):
        assert var_loader.build_nocp_task_vars("test", task="test", config_dir=str(test_config_dir)) == {
            "default": "override",
            "new_field": "merge"
        }
