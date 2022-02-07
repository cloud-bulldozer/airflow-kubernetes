
from openshift_nightlies.models.release import OpenshiftRelease
import pytest
import requests_mock

class TestOpenshiftRelease():
    def test_create_empty_release(self):
        with pytest.raises(TypeError):
            my_release = OpenshiftRelease()
        
    def test_get_release_name(self, valid_openshift_release):
        assert valid_openshift_release.get_release_name() == "version-platform-variant"