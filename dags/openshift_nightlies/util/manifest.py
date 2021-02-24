import yaml


class Manifest():
    def __init__(self, root_dag_dir): 
        with open(f"{root_dag_dir}/manifest.yaml") as manifest_file:
            try:
                self.yaml =  yaml.safe_load(manifest_file)
            except yaml.YAMLError as exc:
                print(exc)


    def get_indexing(self):
        return self.yaml.get('indexing', {})

    def get_releases(self): 
        return self.yaml.get('releases', [])
