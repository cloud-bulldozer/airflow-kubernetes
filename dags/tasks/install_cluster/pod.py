from kubernetes.client import models as k8s

scale_ci_deploy_pod = k8s.V1Pod(
    spec=k8s.V1PodSpec(
        containers=[
            k8s.V1Container(
                name="base",
                image="willhallonline/ansible:latest",
                volume_mounts=[
                    k8s.V1VolumeMount(mount_path="/tmp/", name="example-kubernetes-test-volume")
                ],
            )
        ],
        volumes=[
            k8s.V1Volume(
                name="example-kubernetes-test-volume",
                host_path=k8s.V1HostPathVolumeSource(path="/tmp/"),
            )
        ],
    )
),