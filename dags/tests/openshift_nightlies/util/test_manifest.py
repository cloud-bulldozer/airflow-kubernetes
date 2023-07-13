import pytest
import unittest

from airflow.models import Variable
from openshift_nightlies.util import manifest
from os import environ
from unittest.mock import patch

class TestManifest():
    release_stream_base_url = "https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com/api/v1/releasestream"
    stream = "4.12.0-0.nightly"
    versions = { "4.12" }
    year = "2023"
    INSTALL_BINARY="openshift_install_binary_url"
    CLIENT_BINARY="openshift_client_location"

    @pytest.fixture(scope="session")
    @patch.dict('os.environ', AIRFLOW_VAR_RELEASE_STREAM_BASE_URL=release_stream_base_url)
    def mocked_manifest(self):
        man = manifest.Manifest("openshift_nightlies")
        return man

    @pytest.fixture(scope="session")
    @patch.dict('os.environ', GIT_REPO="https://github.com/FOO/repo")
    def mocked_releases(self,mocked_manifest):
        return mocked_manifest.get_releases()

    def test_manifest_patched_secret_populates(self,mocked_manifest):
        assert len( mocked_manifest.latest_releases ) == 6

    def assert_amd_installer(self,stream):
        assert "arm64" not in stream
        assert "openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.12.0-0.nightly-"+ self.year in stream
        assert "openshift-install-linux-4.12.0-0.nightly-"+ self.year in stream

    def assert_amd_client(self,stream):
        assert "arm64" not in stream
        assert "openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.12.0-0.nightly-"+ self.year in stream
        assert "openshift-client-linux-4.12.0-0.nightly-"+ self.year in stream

    def test_manifest_amd(self,mocked_manifest):
        stream = mocked_manifest.latest_releases[self.stream]
        self.assert_amd_installer(stream[self.INSTALL_BINARY])
        self.assert_amd_client(stream[self.CLIENT_BINARY])

    def assert_arm_installer(self,stream):
        assert "arm64" in stream
        assert "openshift-release-artifacts-arm64.apps.ci.l2s4.p1.openshiftapps.com/4.12.0-0.nightly-arm64-"+ self.year in stream
        assert "openshift-install-linux-amd64-4.12.0-0.nightly-arm64-"+ self.year in stream

    def assert_arm_client(self,stream):
        assert "arm64" in stream
        assert "openshift-release-artifacts-arm64.apps.ci.l2s4.p1.openshiftapps.com/4.12.0-0.nightly-arm64-"+self.year in stream
        assert "openshift-client-linux-amd64-4.12.0-0.nightly-arm64-"+self.year in stream

    def test_manifest_arm(self,mocked_manifest):
        stream = mocked_manifest.latest_releases[f"{self.stream}-arm64"]
        self.assert_arm_installer(stream[self.INSTALL_BINARY])
        self.assert_arm_client(stream[self.CLIENT_BINARY])

    def test_cloudreleases_amd(self,mocked_releases):
        releases = mocked_releases
        hits = 0
        for release in releases:
            release_name = release["release"].get_release_name()
            if "4.12-aws" in release_name and "arm" not in release_name:
                self.assert_amd_installer(release["release"].get_latest_release()[self.INSTALL_BINARY])
                self.assert_amd_client(release["release"].get_latest_release()[self.CLIENT_BINARY])
                hits += 1
        assert hits == 4

    def test_endwith(self):
        assert "aws-arm".endswith("arm")
