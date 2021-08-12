from openshift_nightlies.models.dag_config import DagConfig

class TestDagConfig():
    def test_create_empty_config(self):
        my_config = DagConfig()
        assert True

