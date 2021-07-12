import yaml
sys.path.insert(0, dirname(abspath(dirname(__file__))))
from models.dag_config import DagConfig
from models.release import OpenshiftRelease, BaremetalRelease

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
            schedule = self._get_schedule_for_platform('cloud')
            for cloud_provider in version['providers']:
                platform_name = cloud_provider['name']
                for profile in cloud_provider['profiles']:
                    release = OpenshiftRelease(
                        platform=platform_name,
                        version=version_number,
                        release_stream=release_stream,
                        profile=profile,
                        version_alias=version_alias
                    )
                    dag_config = DagConfig(
                        schedule_interval=schedule
                    )

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
                dag_config = DagConfig(
                    schedule_interval=schedule
                )

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
                dag_config = DagConfig(
                    schedule_interval=schedule
                )

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
        return self.releases

    def _get_schedule_for_platform(self, platform):
        schedules = self.yaml['schedules']
        if bool(schedules.get("enabled", False)):
            return schedules.get(platform, schedules['default'])
        else:
            return None
