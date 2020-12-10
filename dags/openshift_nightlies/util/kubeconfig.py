from os import environ


def get_kubeconfig_volume(version, platform, profile):
    return {
        "name": "kubeconfig",
        "secret": {
            "secretName": f"{version}-{platform}-{profile}-kubeconfig"
        }
    }

def get_kubeconfig_volume_mount():
    return {
        "name": "kubeconfig",
        "mountPath": "~/.kube/config",
        "readOnly": True
    }