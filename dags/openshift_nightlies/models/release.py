from dataclasses import dataclass
sys.path.insert(0, dirname(abspath(dirname(__file__))))
from utils import var_loader

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

    def get_latest_release(self) -> dict: 
        return var_loader.get_latest_release_from_stream(self.release_stream)

@dataclass
class BaremetalRelease(OpenshiftRelease):
    """Class for baremetal releases as it needs a build field"""
    build: str

    # Baremetal doesn't get it's release from a release stream
    def get_latest_release(self) -> dict:
        return {}



