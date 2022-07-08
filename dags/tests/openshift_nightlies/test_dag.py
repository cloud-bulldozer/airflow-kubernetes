import glob
from os import path, environ
import pytest
import requests_mock
from airflow import models as airflow_models
from airflow.utils import dag_cycle_tester 


def variable_patch(name, deserialize_json=False):
    if deserialize_json:
        return {
            "rosa_token_staging": "stub",
            "aws_access_key_id": "stub",
            "aws_secret_access_key": "stub",
            "aws_region_for_openshift": "stub",
            "aws_account_id": "stub",
            "server": "stub",
            "username": "stub",
            "password": "stub",
            "sshkey_token": "stub",
            "osp_orchestration_user": "stub",
            "osp_sshkey_token": "stub",
            "osp_orchestration_host": "stub",
            "orchestration_user": "stub",
            "orchestration_host": "stub",
            "ocm_token": "stub",
            "database": "stub"
        }
    elif name == 'release_stream_base_url':
        return "http://test.com"
    else:
        return ""

class TestDags():

    DAG_PATHS = glob.glob(path.join(path.dirname(__file__), "..", "..", "*", "dag.py"))
    
    

    # def test_dags_compile(self, mocker):
    #     mocker.patch('airflow.models.Variable.get')

    @pytest.mark.parametrize("dag_path", DAG_PATHS)
    def test_dag_integrity(self, dag_path, mocker):
        mocker.patch.object(
            airflow_models.Variable,
            'get',
            side_effect=variable_patch
            )
        environ['GIT_REPO'] = "https://github.com/FOO/repo"
        environ['GIT_BRANCH'] = "BAR"
        with requests_mock.Mocker() as mock: 
            mock_response = {
                "name": "foo",
                "downloadURL": "http://artifact.com"
            }
            mock.get(requests_mock.ANY, json=mock_response)

            """Import DAG files and check for a valid DAG instance."""
            dag_name = path.basename(dag_path)
            module = _import_file(dag_name, dag_path)
            # Validate if there is at least 1 DAG object in the file
            dag_objects = [var for var in vars(module).values() if isinstance(var, airflow_models.dag.DAG)]
            assert dag_objects
            # For every DAG object, test for cycles
            for dag in dag_objects:
                dag.tree_view()
                dag_cycle_tester.check_cycle(dag)
    
def _import_file(module_name, module_path):
    import importlib.util
    spec = importlib.util.spec_from_file_location(module_name, str(module_path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
