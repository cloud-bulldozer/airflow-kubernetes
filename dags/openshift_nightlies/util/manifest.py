import yaml
import requests
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
        self.release_stream_base_url = var_loader.get_secret("release_stream_base_url")
        self.get_latest_releases()

    def get_latest_releases(self): 
        release_streams = [ version['releaseStream'] for version in self.yaml['versions']]
        self.latest_releases = {}
        for stream in release_streams:
            url = f"{self.release_stream_base_url}/{stream}/latest"
            response  = requests.get(url)
            if response.status_code != 200: 
                raise Exception(f"Can't get latest release from OpenShift Release API, API Returned {response.status_code}, {url}")

            payload = response.json()
            latest_accepted_release = payload["name"]
            latest_accepted_release_url = payload["downloadURL"]
            self.latest_releases[stream] = {
                "openshift_client_location": f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}.tar.gz",
                "openshift_install_binary_url": f"{latest_accepted_release_url}/openshift-install-linux-{latest_accepted_release}.tar.gz"
            }
                

    def get_cloud_releases(self):
        cloud = self.yaml['platforms']['cloud']
        for version in self.yaml['versions']:
            if version['version'] in cloud['versions']:
                for provider in cloud['providers']:
                    version_number = version['version']
                    release_stream = version['releaseStream']
                    version_alias = version['releaseStream']
                    for variant in cloud['variants']:
                        platform_name = provider
                        config = variant['config'].copy()
                        config['install'] = f"{provider}/{variant['config']['install']}"
                        release = OpenshiftRelease(
                            platform=platform_name,
                            version=version_number,
                            release_stream=release_stream,
                            latest_release=self.latest_releases[release_stream],
                            variant=variant['name'],
                            config=config,
                            version_alias=version_alias
                        )
                        schedule = self._get_schedule(variant, 'cloud')
                        dag_config = self._build_dag_config(schedule)
                        self.releases.append(
                            {
                                "config": dag_config,
                                "release": release
                            }
                        )

    def get_baremetal_releases(self):
        baremetal = self.yaml['platforms']['baremetal']
        for version in self.yaml['versions']:
            if version['version'] in baremetal['versions']:
                version_number = version['version']
                release_stream = version['baremetalReleaseStream']
                version_alias = version['alias']
                build = baremetal['build']
                for variant in baremetal['variants']:
                    release = BaremetalRelease(
                        platform="baremetal",
                        version=version_number,
                        release_stream=release_stream,
                        variant=variant['name'],
                        config=variant['config'],
                        version_alias=version_alias,
                        latest_release={}, # baremetal builds dont use this
                        build=build
                    )
                    schedule = self._get_schedule(variant, 'baremetal')
                    dag_config = self._build_dag_config(schedule)

                    self.releases.append(
                        {
                            "config": dag_config,
                            "release": release
                        }
                    )

    def get_openstack_releases(self):
        openstack = self.yaml['platforms']['openstack']
        for version in self.yaml['versions']:
            if version['version'] in openstack['versions']:
                version_number = version['version']
                release_stream = version['releaseStream']
                version_alias = version['alias']
                for variant in openstack['variants']:
                    release = OpenshiftRelease(
                        platform="openstack",
                        version=version_number,
                        release_stream=release_stream,
                        latest_release=self.latest_releases[release_stream],
                        variant=variant['name'],
                        config=variant['config'],
                        version_alias=version_alias
                    )
                    schedule = self._get_schedule(variant, 'openstack')
                    dag_config = self._build_dag_config(schedule)

                    self.releases.append(
                        {
                            "config": dag_config,
                            "release": release
                        }
                    )

    def get_rosa_releases(self):
        rosa = self.yaml['platforms']['rosa']
        for version in self.yaml['versions']:
            if version['version'] in rosa['versions']:
                version_number = version['version']
                release_stream = version['releaseStream']
                version_alias = version['alias']
                for variant in rosa['variants']:
                    release = OpenshiftRelease(
                        platform="rosa",
                        version=version_number,
                        release_stream=release_stream,
                        latest_release=self.latest_releases[release_stream],
                        variant=variant['name'],
                        config=variant['config'],
                        version_alias=version_alias
                    )
                    schedule = self._get_schedule(variant, 'rosa')
                    dag_config = self._build_dag_config(schedule)

                    self.releases.append(
                        {
                            "config": dag_config,
                            "release": release
                        }
                    )

    def get_rogcp_releases(self):
        rogcp = self.yaml['platforms']['rogcp']
        for version in self.yaml['versions']:
            if version['version'] in rogcp['versions']:
                version_number = version['version']
                release_stream = version['releaseStream']
                version_alias = version['alias']
                for variant in rogcp['variants']:
                    release = OpenshiftRelease(
                        platform="rogcp",
                        version=version_number,
                        release_stream=release_stream,
                        latest_release=self.latest_releases[release_stream],
                        variant=variant['name'],
                        config=variant['config'],
                        version_alias=version_alias
                    )
                    schedule = self._get_schedule(variant, 'rogcp')
                    dag_config = self._build_dag_config(schedule)

                    self.releases.append(
                        {
                            "config": dag_config,
                            "release": release
                        }
                    )
    def get_prebuilt_releases(self):
        prebuilt = self.yaml['platforms']['prebuilt']
        for variant in prebuilt['variants']:
            release = OpenshiftRelease(
                platform="prebuilt",
                version="4.x",
                release_stream="",
                latest_release={},
                variant=variant['name'],
                config=variant['config'],
                version_alias=""
            )
            schedule = self._get_schedule(variant, 'prebuilt')
            dag_config = self._build_dag_config(schedule)

            self.releases.append(
                {
                    "config": dag_config,
                    "release": release
                }
            )



    def get_releases(self):
        if 'cloud' in self.yaml['platforms']:
            self.get_cloud_releases()
        if 'baremetal' in self.yaml['platforms']:
            self.get_baremetal_releases()
        if 'openstack' in self.yaml['platforms']:
            self.get_openstack_releases()
        if 'rosa' in self.yaml['platforms']:
            self.get_rosa_releases()
        if 'rogcp' in self.yaml['platforms']:
            self.get_rogcp_releases()
        if 'prebuilt' in self.yaml['platforms']:
            self.get_prebuilt_releases()
        return self.releases

    def _get_dependencies(self):
        dependencies = {}
        for dep_name, dep_value in self.yaml['dagConfig']['dependencies'].items():
            dependencies[f"{dep_name}_repo".upper()] = dep_value['repo']
            dependencies[f"{dep_name}_branch".upper()] = dep_value['branch']
        return dependencies

    def _get_schedule(self, variant, platform):
        schedules = self.yaml['dagConfig']['schedules']
        if bool(schedules.get("enabled", False): # and var_loader.get_git_user() == "cloud-bulldozer"):
            return variant.get('schedule', schedules.get(platform, schedules['default']))
        else:
            return None
    
    def _build_dag_config(self, schedule_interval):
        return DagConfig(
            schedule_interval=schedule_interval,
            cleanup_on_success=bool(self.yaml['dagConfig']['cleanupOnSuccess']),
            executor_image=self.yaml['dagConfig'].get('executorImages', None),
            dependencies=self._get_dependencies()
        )
