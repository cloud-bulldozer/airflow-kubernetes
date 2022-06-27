from airflow.models import Variable
from openshift_nightlies.util import var_loader
from os import environ
from unittest import mock

class TestVarLoader():
    def test_get_git_user(self):
        environ['GIT_REPO'] = "https://github.com/FOO/repo"
        environ['GIT_BRANCH'] = "BAR"
        assert var_loader.get_git_user() == "foo"

    def test_get_secret(self, mocker):
        mocker.patch('airflow.models.Variable.get')
        var_loader.get_secret("foo")
        Variable.get.assert_called_once_with("foo", deserialize_json=False)

    def test_get_secret_patched(self):
        with mock.patch.dict('os.environ', AIRFLOW_VAR_RELEASE_STREAM_BASE_URL="https://a.b.c:6443/path/to"):
            assert "https://a.b.c:6443/path/to" == Variable.get("release_stream_base_url")

    def test_get_default_task_vars(self, valid_openshift_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_openshift_release, task="test", task_dir=str(test_tasks_dir)) == {
            "task": "test", 
            "default": "foo",
            "platform": None
        } 

    def test_get_default_task_vars(self, valid_openshift_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_openshift_release, task_dir=str(test_tasks_dir)) == {
            "task": "install", 
            "default": "foo",
            "platform": "platform"
        } 

    # Asserting 'platform' here only tests var_loader.get_default_task_vars branches, but we don't want to replicate the production logic in the test harness.
    def test_get_default_task_vars_cloud(self, valid_aws_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_aws_release, task_dir=str(test_tasks_dir)) == {
            "task": "install", 
            "default": "foo",
            "platform": "cloud"
        }

    def test_get_default_task_vars_aws_arm(self, valid_aws_arm_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_aws_arm_release, task_dir=str(test_tasks_dir)) == {
            "task": "install", 
            "default": "foo",
            "platform": "cloud"
        }

    def test_get_default_task_vars_gcp(self, valid_gcp_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_gcp_release, task_dir=str(test_tasks_dir)) == {
            "task": "install", 
            "default": "foo",
            "platform": "cloud"
        }

    def test_get_default_task_vars_alibaba(self, valid_alibaba_release, test_tasks_dir):
        assert var_loader.get_default_task_vars(valid_alibaba_release, task_dir=str(test_tasks_dir)) == {
            "task": "install", 
            "default": "foo",
            "platform": "cloud"
        }

    
    def test_get_config_vars(self, valid_openshift_release, test_config_dir):
        assert var_loader.get_config_vars(valid_openshift_release, task="test", config_dir=str(test_config_dir)) == { 
            "default": "override",
            "new_field": "merge"
        } 

    def test_build_task_vars(self, valid_openshift_release, test_config_dir, test_tasks_dir):
        assert var_loader.build_task_vars(valid_openshift_release, task="test", config_dir=str(test_config_dir), task_dir=str(test_tasks_dir)) == {
            "task": "test", 
            "default": "override",
            "new_field": "merge",
            "platform": None
        }
