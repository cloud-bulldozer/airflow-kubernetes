# Manifest and Releases

## Overview

This project has two top level terms essential in understanding how this project works:

* `release`: A unique installation of Openshift.
* `manifest`: A list of releases to generate nightly performance and scale pipelines for

## Releases

A `release` is simply a unique installation of Openshift and are defined in two places: the `configs` directory ([More about that directory](./variables.md)) and the `manifest.yaml`. 

Strictly speaking, a `release` is actually a unique combination of configurations defined in the manifest:

1. `version` refers to the openshift release (i.e. 4.7)
2. `platform` refers to the platform openshift is being installed on (i.e. cloud/baremetal)
3. `variant` refers to a specific configuration of install/benchmarks (i.e. ovn)

> Note: For the "cloud" platform there is also the "provider" field which determines what cloud provider to use. 

## Variants

A `variant` is a combination of install and benchmark configurations. This is not directly represented in code but is functionally defined in the manifest.

## Manifest

The manifest is just the `manifest.yaml` file that defines the releases. The `dag.py` script will read that file in and generate the DAGs accordingly.

Airflow will use the provided credentials to login to your specified cluster to run the benchmarks used for that dag.
In the manifest the `version` and `provider` (cloud-only) fields are applied to all variants for that platform. So for instance:

```yaml

platforms:
  cloud:
    versions: ["4.11", "4.12"]
    providers: ["aws", "gcp", "azure"]
    variants: 
    - name: sdn-control-plane
      schedule:  "0 12 * * 1,3,5"
      config: 
        install: sdn.json
        benchmarks: control-plane.json  
  openstack:
    versions: ["4.11", "4.12"]
    variants:
      - name: sdn
        config:
          install: openstack/sdn.json
          benchmarks: openstack.json
```

would create a total of 8 dags ( 6 cloud-based, 2 openstack) with the naming convention being `$version-$provider-$variant`. This is because there is no fundamental parameter differences required between versions/providers, and this behavior gives us confidence that we're testing the same configurations across different versions and/or platforms.

The children of the "config" section tell where under config to look for the definitions.
For cloud platforms, each `provider` value is a sub-directory of `config/install`.
See [variables.md](./variables.md) for more detail about variables.

`./util/manifest.py` parses the manifest YAML and expands the variants to run, including:

* resolving the installer and client binaries
* expanding the versions/platforms/variants from `manifest.yaml` into OpenshiftReleases.

## Prebuilt Clusters

To run a dag using an already existing cluster, you can make use of the 2 prebuilt dags, ie 4.x-prebuilt-data-plane and 4.x-prebuilt-control-plane. 

These dags can only be triggered manually and have to be triggered using the "Trigger with config option" upon which you will be prompted to enter the openshift credentials in json format.
```
{
    "KUBEUSER": "<Enter openshift cluster-admin username>",
    "KUBEPASSWORD": "<Enter openshift cluster password>",
    "KUBEURL": "<Enter cluster URL>"
}