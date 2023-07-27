from dataclasses import dataclass
from typing import Optional
from os import environ
from hashlib import md5

@dataclass
class OpenshiftRelease:
    """Class used to define a unique release"""
    platform: str  # e.g. aws
    version: str # e.g. 4.7
    release_stream: str # The actual release stream to pull from (nightly/stable/ci)
    variant: str # e.g. default/ovn
    config: dict # points to task configs
    version_alias: Optional[str] # e.g. stable/.next/.future
    latest_release: Optional[dict] # populated at runtime by hitting upstream openshift api
    
    def get_release_name(self, delimiter="-") -> str:
        if self.platform in self.variant:  
            return f"{self.version}{delimiter}{self.variant}"
        else: 
            return f"{self.version}{delimiter}{self.platform}{delimiter}{self.variant}"
            
    def get_latest_release(self) -> dict: 
        return self.latest_release
            
        

    # Used to get the git user for the repo the dags live in.
    def _get_git_user(self):
        git_repo = environ['GIT_REPO']
        git_path = git_repo.split("https://github.com/")[1]
        git_user = git_path.split('/')[0]
        return git_user.lower()

    def _generate_cluster_name(self):
        git_user = self._get_git_user()
        git_branch = str(environ['GIT_BRANCH']).replace("_","-").lower()
        release_name = self.get_release_name(delimiter="-")
        if git_user == 'cloud-bulldozer':
            cluster_name = f"ci-{release_name}"
        else:
            cluster_name = f"{git_user}-{git_branch}-{release_name}"

        if self.platform == 'rosa' or self.platform == 'rogcp' or self.platform == 'hypershift' or self.platform == 'rosahcp':
            #Only 15 chars are allowed
            cluster_version = str(self.version).replace(".","")
            return "perf-"+md5(cluster_name.encode("ascii")).hexdigest()[:3]
        elif self.platform == 'alibaba':
            # "." is not allowed in the cluster name while creating private network.
            cluster_name = str(cluster_name).replace(".","-")
            return cluster_name
        else:
            return cluster_name
    

@dataclass
class BaremetalRelease(OpenshiftRelease):
    """Class for baremetal releases as it needs a build field"""
    build: str

    # Baremetal doesn't get it's release from a release stream
    def get_latest_release(self) -> dict:
        return {}
