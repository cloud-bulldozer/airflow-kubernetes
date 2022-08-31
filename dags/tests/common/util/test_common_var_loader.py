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
