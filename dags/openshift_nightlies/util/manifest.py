import yaml

# Base Directory where all OpenShift Nightly DAG Code lives
root_dag_dir = "/opt/airflow/dags/repo/dags/openshift_nightlies"


class Manifest():
    def __init__(self, root_dag_dir): 
        with open(f"{root_dag_dir}/manifest.yaml") as manifest_file:
            try:
                self.yaml =  yaml.safe_load(manifest_file)
            except yaml.YAMLError as exc:
                print(exc)


    def get_defaults(self):
        return self.yaml.get('defaults', {})

    def get_releases(self): 
        yield self.yaml.get('releases', [])
