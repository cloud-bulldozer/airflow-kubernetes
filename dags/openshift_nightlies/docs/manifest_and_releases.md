# Manifest and Releases

## Overview

This project has two top level terms essential in understanding how this project works:

* `release`: A unique installation of Openshift.
* `manifest`: A list of releases to generate nightly performance and scale pipelines for

## Releases

A `release` is simply a unique installation of Openshift and are defined in two places: the `releases` directory ([More about that directory](./variables.md)) and the `manifest.yaml`. 

Strictly speaking, a `release` is actually a unique combination of three variables defined in the manifest: `version`, `platform`, and `profile`:

1. `version` refers to the openshift release (i.e. 4.7)
2. `platform` refers to the platform openshift is being installed on (i.e. aws)
3. `profile` refers to a specific configuration within that release+platform (i.e. ovn)


This data is used to generate a dag and load in the variables defined in the `releases` directory accordingly. Airflow also names the dag based off of it. Adding a second release with the same values for all three of these parameters would essentialy create duplicate DAGs, so you don't want to do that. 
### Platform vs. Providers

In the manifest, all cloud releases are underneath a "cloud" umbrella platform. However, each cloud version also has a "providers" key which determines the Cloud provider to install OpenShift on. In this case, the Provider is used as the platform. 



## Manifest

The manifest is just the `manifest.yaml` file that defines the releases. The `dag.py` script will read that file in and generate the DAGs accordingly.

