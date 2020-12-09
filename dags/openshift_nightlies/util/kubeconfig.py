from os import environ


def get_kubeconfig_volume():
    return {
        "name": "kubeconfig",
        "secret": {
            "secretName": f"{environ.get('AIRFLOW_CTX_DAG_ID', 'test')}-kubeconfig"
        }
    }

def get_kubeconfig_volume_mount():
    return {
        "name": "kubeconfig",
        "mountPath": "~/.kube/config",
        "readOnly": True
    }