
from openshift_nightlies.models.release import OpenshiftRelease
import pytest
import requests_mock

class TestOpenshiftRelease():
    def test_create_empty_release(self):
        with pytest.raises(TypeError):
            my_release = OpenshiftRelease()
        
    def test_get_release_name(self, valid_openshift_release):
        assert valid_openshift_release.get_release_name() == "version_platform_profile"

    
    def test_get_latest_release(self, valid_openshift_release):
        with requests_mock.Mocker() as mock: 
            base_url = "http://test.com"
            full_url = f"{base_url}/{valid_openshift_release.release_stream}/latest"
            mock_response = {
                "name": "foo",
                "downloadURL": "http://artifact.com"
            }
            mock.get(full_url, json=mock_response)

            expected_result = {
                "openshift_client_location": "http://artifact.com/openshift-client-linux-foo.tar.gz",
                "openshift_install_binary_url": "http://artifact.com/openshift-install-linux-foo.tar.gz"
            }

            assert expected_result == valid_openshift_release.get_latest_release(base_url)