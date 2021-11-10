import sys
from os.path import abspath, dirname
from os import environ
from kubernetes.client import models as k8s
sys.path.insert(0, dirname(abspath(dirname(__file__))))
from models.release import OpenshiftRelease



def get_kubeadmin_password(release: OpenshiftRelease): 
    return k8s.V1EnvVar(
        name="KUBEADMIN_PASSWORD",
        value_from=k8s.V1EnvVarSource(
            secret_key_ref= k8s.V1SecretKeySelector(
                name=f"{release.get_release_name()}-kubeadmin",
                key="KUBEADMIN_PASSWORD",
                optional=True
            )
        )
    )

def get_kubeconfig_volume(release: OpenshiftRelease):
    return k8s.V1Volume(
        name="kubeconfig",
        secret=k8s.V1SecretVolumeSource(
            secret_name=f"{release.get_release_name()}-kubeconfig"
        )
    )

def get_kubeconfig_volume_mount():
    return k8s.V1VolumeMount(
        name="kubeconfig",
        mount_path="/home/airflow/.kube",
        read_only=True
    )

def get_empty_dir_volume_mount():
    return k8s.V1VolumeMount(
        name="tmpdir",
        mount_path="/tmp"
    )

def get_empty_dir_volume():
    return k8s.V1Volume(
        name="tmpdir",
        empty_dir=k8s.V1EmptyDirVolumeSource()
    )
