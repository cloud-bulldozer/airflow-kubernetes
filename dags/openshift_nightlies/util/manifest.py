import yaml
from openshift_nightlies.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease, BaremetalRelease
from openshift_nightlies.util import var_loader

class Manifest():
    def __init__(self, root_dag_dir):
        with open(f"{root_dag_dir}/manifest.yaml") as manifest_file:
            try:
                self.yaml = yaml.safe_load(manifest_file)
            except yaml.YAMLError as exc:
                print(exc)
        self.releases = []

    def get_version_alias(self, version):
        aliases = self.yaml['versionAliases']
        return [alias['alias'] for alias in aliases if alias['version'] == version][0]

    def get_cloud_releases(self):
        for version in self.yaml['platforms'].get('cloud', []):
            version_number = version['version']
            release_stream = version['releaseStream']
            version_alias = self.get_version_alias(version_number)
            
            for cloud_provider in version['providers']:
                platform_name = cloud_provider['name']
                for profile in cloud_provider['profiles']:
                    schedule = self._get_schedule_for_platform(str(profile))
                    release = OpenshiftRelease(
                        platform=platform_name,
                        version=version_number,
                        release_stream=release_stream,
                        profile=profile,
                        version_alias=version_alias
                    )
                    dag_config = self._build_dag_config(schedule)

                    self.releases.append(
                        {
                            "config": dag_config,
                            "release": release
                        }
                    )

    def get_baremetal_releases(self):
        for version in self.yaml['platforms'].get('baremetal', []):
            version_number = version['version']
            release_stream = version['releaseStream']
            build = version['build']
            schedule = self._get_schedule_for_platform('baremetal')
            version_alias = self.get_version_alias(version_number)
            for profile in version['profiles']:
                release = BaremetalRelease(
                    platform="baremetal",
                    version=version_number,
                    release_stream=release_stream,
                    profile=profile,
                    version_alias=version_alias,
                    build=build
                )
                dag_config = self._build_dag_config(schedule)

                self.releases.append(
                    {
                        "config": dag_config,
                        "release": release
                    }
                )

    def get_openstack_releases(self):
        for version in self.yaml['platforms'].get('openstack', []):
            version_number = version['version']
            release_stream = version['releaseStream']
            version_alias = self.get_version_alias(version_number)
            schedule = self._get_schedule_for_platform('openstack')
            for profile in version['profiles']:
                release = OpenshiftRelease(
                    platform="openstack",
                    version=version_number,
                    release_stream=release_stream,
                    profile=profile,
                    version_alias=version_alias
                )
                dag_config = self._build_dag_config(schedule)

                self.releases.append(
                    {
                        "config": dag_config,
                        "release": release
                    }
                )

    def get_rosa_releases(self):
        for version in self.yaml['platforms'].get('rosa', []):
            version_number = version['version']
            release_stream = version['releaseStream']
            version_alias = self.get_version_alias(version_number)
            schedule = self._get_schedule_for_platform('rosa')
            for profile in version['profiles']:
                release = OpenshiftRelease(
                    platform="rosa",
                    version=version_number,
                    release_stream=release_stream,
                    profile=profile,
                    version_alias=version_alias
                )
                dag_config = self._build_dag_config(schedule)

                self.releases.append(
                    {
                        "config": dag_config,
                        "release": release
                    }
                )

    def get_releases(self):
        self.get_cloud_releases()
        self.get_baremetal_releases()
        self.get_openstack_releases()
        self.get_rosa_releases()
        return self.releases

    def _get_dependencies(self):
        dependencies = {}
        for dep_name, dep_value in self.yaml['dagConfig']['dependencies'].items():
            dependencies[f"{dep_name}_repo".upper()] = dep_value['repo']
            dependencies[f"{dep_name}_branch".upper()] = dep_value['branch']
        return dependencies

    def _get_schedule_for_platform(self, platform):
        schedules = self.yaml['dagConfig']['schedules']
        if bool(schedules.get("enabled", False)): # and var_loader.get_git_user() == "cloud-bulldozer"):
            return schedules.get(platform, schedules['default'])
        else:
            return None
    
    def _build_dag_config(self, schedule_interval):
        return DagConfig(
            schedule_interval=schedule_interval,
            cleanup_on_success=bool(self.yaml['dagConfig']['cleanupOnSuccess']),
            executor_image=self.yaml['dagConfig'].get('executorImages', None),
            dependencies=self._get_dependencies()
        )
