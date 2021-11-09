from kubernetes.client import models as k8s
from openshift_nightlies.models.release import OpenshiftRelease
from openshift_nightlies.models.dag_config import DagConfig


def get_default_executor_config(dag_config: DagConfig, executor_image='airflow-ansible'):
    return {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image=f"{dag_config.executor_image['repository']}/{executor_image}:{dag_config.executor_image['tag']}",
                            image_pull_policy="Always",
                            volume_mounts=[
                                get_empty_dir_volume_mount()]

                        )
                    ],
                    volumes=[get_empty_dir_volume_mount()]
                )
            )
        }

def get_executor_config_with_cluster_access(dag_config: DagConfig, release: OpenshiftRelease, executor_image="airflow-ansible"):
    return {
            "pod_override": k8s.V1Pod(
                spec=k8s.V1PodSpec(
                    containers=[
                        k8s.V1Container(
                            name="base",
                            image=f"{dag_config.executor_image['repository']}/{executor_image}:{dag_config.executor_image['tag']}",
                            image_pull_policy="Always",
                            env=[
                                get_kubeadmin_password(release)
                            ],
                            volume_mounts=[
                                get_kubeconfig_volume_mount()]

                        )
                    ],
                    volumes=[get_kubeconfig_volume(release)]
                )
            )
        }


def get_kubeadmin_password(release: OpenshiftRelease): 
    return k8s.V1EnvVar(
        name="KUBEADMIN_PASSWORD",
        value_from=k8s.V1EnvVarSource(
            secret_key_ref= k8s.V1SecretKeySelector(
                name=f"{release.version}-{release.platform}-{release.variant}-kubeadmin",
                key="KUBEADMIN_PASSWORD"
            )
        )
    )

def get_kubeconfig_volume(release: OpenshiftRelease):
    return k8s.V1Volume(
        name="kubeconfig",
        secret=k8s.V1SecretVolumeSource(
            secret_name=f"{release.version}-{release.platform}-{release.variant}-kubeconfig"
        )
    )

def get_kubeconfig_volume_mount():
    return k8s.V1VolumeMount(
        name="kubeconfig",
        mount_path="/home/airflow/auth",
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
