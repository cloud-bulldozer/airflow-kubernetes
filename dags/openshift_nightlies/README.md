# Overview

This directory contains all tasks, scripts, and default vars for openshift nightly performance builds

## Structure

* `dag.py`: The openshift-nightly DAG. If reading through the code, start here, as it outlines the precedence of the tasks in a DAG and wires everything else together.
* `manifest.yaml`: The root-level configuration for all nightly DAGs. Children of 'platforms' are templated out to individual DAGs in airflow. More about [Manifests](./docs/manifest_and_releases.md).
* `config`: Contains benchmark and installation configurations and variable defaults. [See docs/variables.doc for more](./docs/variables.md).
* `docs`: Documentation for how the DAGs work and are wired together.
* `models`: Contains two @dataclass classes used throughout. Honestly, the code is not strictly organized as there are plenty of classes defined in other directories.
* `scripts`: Contains any executable run by an Airflow task
* `tasks`: Contains python setup for Airflow Tasks
* `util`: Contains utility functions for Airflow