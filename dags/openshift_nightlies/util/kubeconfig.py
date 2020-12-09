from os import environ


def get_kubeconfig_volume():
    dag_id_no_underscores = environ.get('AIRFLOW_CTX_DAG_ID', 'test').replace("_", "-")
    return {
        "name": "kubeconfig",
        "secret": {
            "secretName": f"{dag_id_no_underscores}-kubeconfig"
        }
    }

def get_kubeconfig_volume_mount():
    return {
        "name": "kubeconfig",
        "mountPath": "~/.kube/config",
        "readOnly": True
    }