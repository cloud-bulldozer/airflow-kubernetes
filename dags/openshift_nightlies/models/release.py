import sys
from os.path import abspath, dirname
from dataclasses import dataclass
from typing import Optional
sys.path.insert(0, dirname(abspath(dirname(__file__))))

@dataclass
class OpenshiftRelease:
    """Class used to define a unique release"""
    platform: str  # e.g. aws
    version: str # e.g. 4.7
    release_stream: str # The actual release stream to pull from (nightly/stable/ci)
    profile: str # e.g. default/ovn
    version_alias: Optional[str] # e.g. stable/.next/.future

    def get_release_name(self) -> str: 
        return f"{self.version}_{self.platform}_{self.profile}"
    
    def get_release_name(self, delimiter) -> str:
        return f"{self.version}{delimiter}{self.platform}{delimiter}{self.profile}"

    def get_latest_release(self, base_url) -> dict: 
        url = f"{base_url}/{self.release_stream}/latest"
        payload = requests.get(url).json()
        latest_accepted_release = payload["name"]
        latest_accepted_release_url = payload["downloadURL"]
        return {
            "openshift_client_location": f"{latest_accepted_release_url}/openshift-client-linux-{latest_accepted_release}.tar.gz",
            "openshift_install_binary_url": f"{latest_accepted_release_url}/openshift-install-linux-{latest_accepted_release}.tar.gz"
        }
    

@dataclass
class BaremetalRelease(OpenshiftRelease):
    """Class for baremetal releases as it needs a build field"""
    build: str

    # Baremetal doesn't get it's release from a release stream
    def get_latest_release(self) -> dict:
        return {}



