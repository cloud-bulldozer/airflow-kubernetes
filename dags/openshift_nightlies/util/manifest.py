import yaml


class Manifest():
    def __init__(self, root_dag_dir): 
        with open(f"{root_dag_dir}/manifest.yaml") as manifest_file:
            try:
                self.yaml =  yaml.safe_load(manifest_file)
            except yaml.YAMLError as exc:
                print(exc)
        self.releases = []


    def get_version_alias(self, version):
        aliases = self.yaml['versionAliases']
        return [alias['alias'] for alias in aliases if alias['version'] == version][0]

    def get_cloud_releases(self):
        for version in self.yaml['platforms']['cloud']: 
            version_number = version['version']
            release_stream = version['releaseStream']
            version_alias = self.get_version_alias(version_number)
            for cloud_provider in version['providers']:
                platform_name = cloud_provider['name']
                for profile in cloud_provider['profiles']:
                    self.releases.append({
                        "version": version_number,
                        "releaseStream": release_stream,
                        "platform": platform_name,
                        "versionAlias": version_alias,
                        "profile": profile
                    })

    def get_baremetal_releases(self):
        for version in self.yaml['platforms']['baremetal']: 
            version_number = version['version']
            release_stream = version['releaseStream']
            build = version['build']
            version_alias = self.get_version_alias(version_number)
            for profile in version['profiles']:
                self.releases.append({
                    "version": version_number,
                    "releaseStream": release_stream,
                    "platform": "baremetal",
                    "build": build,
                    "versionAlias": version_alias,
                    "profile": profile
                })
            
    def get_openstack_releases(self):
        for version in self.yaml['platforms'].get('openstack', []): 
            version_number = version['version']
            release_stream = version['releaseStream']
            version_alias = self.get_version_alias(version_number)
            for profile in version['profiles']:
                self.releases.append({
                    "version": version_number,
                    "releaseStream": release_stream,
                    "platform": "openstack",
                    "versionAlias": version_alias,
                    "profile": profile
                })


    def get_releases(self):
        self.get_cloud_releases()
        self.get_baremetal_releases()
        self.get_openstack_releases()
        return self.releases
