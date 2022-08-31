from common.models.dag_config import DagConfig

class TestDagConfig():
    def test_create_empty_config(self):
        my_config = DagConfig()
        assert my_config.default_args['owner'] == 'airflow'

    def test_create_config_default_args(self):
        my_custom_args = {
            "foo": "bar"
        }
        my_config = DagConfig(default_args=my_custom_args)
        assert my_config.default_args['foo'] == 'bar'
