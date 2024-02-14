# Non-OCP workloads

Dags defined here don't need a OCP cluster and instead use an orchestration host to run the workloads.
Dag definition file (airflow-kubernetes/dags/nocp/dag.py) defines these dags (i.e non OCP based applications).
“OCM” is an example of such an application. Other non-OCP applications can utilize this DAG later.

## Structure

This directory contains all tasks, scripts, and default vars for openshift nightly performance builds

* `dag.py`: The non-ocp DAG. If reading through the code, start here, as it outlines the precedence of the tasks in a DAG and wires everything else together.
* `manifest.yaml`: The root-level configuration for all nightly DAGs. Children of 'platforms' are templated out to individual DAGs in airflow. More about [Manifests](./docs/manifest_and_releases.md).
* `config`: Contains benchmark and installation configurations and variable defaults. [See docs/variables.doc for more](./docs/variables.md).
* `docs`: Documentation for how the DAGs work and are wired together.
* `models`: Contains two @dataclass classes used throughout. Honestly, the code is not strictly organized as there are plenty of classes defined in other directories.
* `scripts`: Contains any executable run by an Airflow task
* `tasks`: Contains python setup for Airflow Tasks
* `util`: Contains utility functions for Airflow

# OCM DAG

This DAG is used for OCM testing. Modules in this DAG -

*1) config/benchmarks/ocm.json*
* Secrets are fetched from the vault.  All config variables defined in this file

*2) manifest.yaml*
* This manifest file defines ocm app and its auto schedule configuration (every Thursday 9am UTC). Auto schedule is only enabled for the Prod. dag

*3) tasks/benchmarks/nocp.py*
* OCM tasks module. Defines the **ocm-api-load** benchmark and **cleanup** tasks.
* ocm-api-load task executes ```run_ocm_benchmark.sh``` with ```ocm-api-load``` operation
* cleanup task executes ```run_ocm_benchmark.sh``` with ```cleanup``` operation

*4) scripts/run_ocm_benchmark.sh*
* Creates a TEMP directory in the orchestration host and uses it to run the ocm-api-load or cleanup scripts.
* Copies environment variables to a file in this TEMP directory.
* Each dag run uses its own TEMP directory to assist in simultaneous dag runs.
* Also both ocm-api-load and cleanup tasks use separate TEMP directories to avoid failures of ocm-api-load impacting cleanup task.
* UUID of ocm-api-load is passed to the cleanup task for removing ocm-api-load config files.

*5) scripts/run_ocm_api_load.sh*
* Defines ocm-api-load tests (end points) with rate and duration. Each test is triggered with this rate and for the specified duration
* Some tests require ```OsdCcsAdmin``` privileges (which are regenerated every time) before the test is started.
* Use the unique TEMP directory (created by run_ocm_benchmark.sh) inside the orchestration host to run the tests.
* Clones ```ocm-api-load``` and build the ```ocm-load-test``` binary
* Each test is called with a timeout.
  ```Timeout = test duration + 10 minutes```
  This extra 10 minutes help test to create necessary result files after running the test for given duration
* Kube burner is used to pull metrics from clusters and account manager services and push to observability ES.
* Finally it displays dashboard URLs for these metrics
* At the end, this script returns UUID and test result to airflow. UUID is used in the next task (i.e cleanup task)

*6) scripts/cleanup_clusters.sh*
* Use the unique TEMP directory (created by run_ocm_benchmark.sh) inside the orchestration host to run the tests.
* It uses “ocm” cli to clean up all clusters. Clusters created by ocm-api-load will have names starting with “pocm-”. First 4 letters of the test UUID are also used in the cluster name. However we are deleting all “pocm-” clusters for the safer side.
