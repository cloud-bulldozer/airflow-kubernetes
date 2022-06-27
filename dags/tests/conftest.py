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
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def valid_aws_release():
    return OpenshiftRelease(
        platform="aws",
        version="version",
        release_stream="release_stream",
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def valid_aws_arm_release():
    return OpenshiftRelease(
        platform="aws-arm",
        version="version",
        release_stream="release_stream",
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def valid_azure_release():
    return OpenshiftRelease(
        platform="azure",
        version="version",
        release_stream="release_stream",
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def valid_gcp_release():
    return OpenshiftRelease(
        platform="gcp",
        version="version",
        release_stream="release_stream",
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def valid_alibaba_release():
    return OpenshiftRelease(
        platform="alibaba",
        version="version",
        release_stream="release_stream",
        variant="variant",
        config={
            "install": "install.json",
            "test": "test.json"
        },
        version_alias="alias",
        latest_release={
            "openshift_client_location": "foo",
            "openshift_install_binary_url": "bar"
        }
    )

@pytest.fixture(scope="session")
def test_config_dir(tmp_path_factory, valid_openshift_release):
    releases_dir = tmp_path_factory.mktemp("config", numbered=False)
    _populate_config_dir(releases_dir, valid_openshift_release, "test")
    return releases_dir

@pytest.fixture(scope="session")
def test_tasks_dir(tmp_path_factory):
    tasks_dir = tmp_path_factory.mktemp("tasks", numbered=False)
    _populate_task_dir(tasks_dir, "test")
    _populate_task_dir(tasks_dir, "install", "platform")
    _populate_task_dir(tasks_dir, "install", "cloud")
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
        platform = "cloud" if platform == 'cloud' else platform
        platform_specific_dir = task_dir / platform
        try:
            platform_specific_dir.mkdir()
        except FileExistsError:
            pass
        with open(f"{platform_specific_dir}/defaults.json", 'w') as f:
            json.dump(default_task_dictionary, f)
    else:
        with open(f"{task_dir}/defaults.json", 'w') as f:
            json.dump(default_task_dictionary, f)



def _populate_config_dir(base_config_dir, release: OpenshiftRelease, task):
    overrides = {
        "default": "override", 
        "new_field": "merge"
    }
    task_dir = base_config_dir / task
    try:
        task_dir.mkdir()
    except FileExistsError:
        pass

    with open(f"{base_config_dir}/{task}/{release.config[task]}", 'w') as f:
            json.dump(overrides, f)