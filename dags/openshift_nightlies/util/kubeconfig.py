from airflow.contrib.kubernetes.secret import Secret
from airflow.kubernetes.volume import Volume
from airflow.kubernetes.volume_mount import VolumeMount
from os import environ


def get_kubeconfig_volume():
    return {
        "name": "kubeconfig",
        "secret": {
            "secretName": f"{environ['AIRFLOW_CTX_DAG_ID']}-kubeconfig"
        }
    }

def get_kubeconfig_volume_mount():
    return {
        "name": "kubeconfig",
        "mountPath": "~/.kube/config",
        "readOnly": True
    }