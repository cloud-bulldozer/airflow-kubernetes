import pytest
import json

from openshift_nightlies.models.dag_config import DagConfig
from openshift_nightlies.models.release import OpenshiftRelease, BaremetalRelease


@pytest.fixture(scope="session")
def valid_openshift_release():
    return OpenshiftRelease(
        platform="platform",
        version="version",
        release_stream="release_stream",
        profile="profile",
        version_alias="alias"
    )

@pytest.fixture(scope="session")
def valid_aws_release():
    return OpenshiftRelease(
        platform="aws",
        version="version",
        release_stream="release_stream",
        profile="profile",
        version_alias="alias"
    )




@pytest.fixture(scope="session")
def test_releases_dir(tmp_path_factory, valid_openshift_release):
    releases_dir = tmp_path_factory.mktemp("releases", numbered=False)
    _populate_releases_dir(releases_dir, valid_openshift_release, "test")
    return releases_dir

@pytest.fixture(scope="session")
def test_tasks_dir(tmp_path_factory):
    tasks_dir = tmp_path_factory.mktemp("tasks", numbered=False)
    _populate_task_dir(tasks_dir, "test")
    _populate_task_dir(tasks_dir, "install", "platform")
    _populate_task_dir(tasks_dir, "install", "aws")
    return tasks_dir



def _populate_task_dir(base_task_dir, task, platform=None):
    default_task_dictionary = {
        "task": task,
        "default": "foo",
        "platform": platform
    }
    task_dir = base_task_dir / task
    try:
        task_dir.mkdir()
    except FileExistsError:
        pass

    if platform is not None:
        platform = "cloud" if platform == 'aws' or platform == 'azure' or platform == 'gcp' else platform
        platform_specific_dir = task_dir / platform
        platform_specific_dir.mkdir()
        with open(f"{platform_specific_dir}/defaults.json", 'w') as f:
            json.dump(default_task_dictionary, f)
    else:
        with open(f"{task_dir}/defaults.json", 'w') as f:
            json.dump(default_task_dictionary, f)



def _populate_releases_dir(base_releases_dir, release: OpenshiftRelease, task):
    version_dir = base_releases_dir / release.version
    try:
        version_dir.mkdir()
    except FileExistsError:
        pass

    platform_dir = version_dir / release.platform

    try:
        platform_dir.mkdir()
    except FileExistsError:
        pass

    profile_dir = platform_dir / release.profile

    try:
        profile_dir.mkdir()
    except FileExistsError:
        pass

    overrides = {
        "default": "override", 
        "new_field": "merge"
    }

    with open(f"{profile_dir}/{task}.json", 'w') as f:
            json.dump(overrides, f)