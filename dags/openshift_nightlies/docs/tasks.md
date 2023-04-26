# Tasks

## Overview

Tasks is a unit of work within Airflow. It is analogous to a Jenkins Stage. These Tasks are defined through one of the `Operator` classes Airflow provides.
For example: If you want to run a shell script as a task in your Airflow DAG, you would use the `BashOperator` class.

## Tasks, TaskModules and TaskPackages

While a `Task` is a unit of work, `TaskModules` and `TaskPackages` are abstractions within this project to make managing Tasks a bit easier.

* A `TaskModule` is just a python module used to create tasks. 
* A `TaskPackage` is a logical grouping of `TaskModules`. 


A TaskModule **should**

* List all of it's variables in it's `defaults.json` or similar documentation
* Be generic enough to extend to other releases without writing extra code 
* Be agnostic to a specific openshift release (the one exception is for the install task as installation varies widely depending on the platform)
* Create generic functions to dynamically configure tasks based off of the release. 

## TaskPackage Structure

Each TaskPackage should have a similar structure to this:

```
tasks
└── $MYTASKPACKAGE
    ├── defaults.json
    ├── __init__.py 
    └── $MYTASKMODULE.py
```

Such that importing the task from the top level `dag.py` looks like this

```python
from tasks.$MYTASKPACKAGE import $MYTASKMODULE

```

> Note: The package name for the task doesn't have to be the same as the module name. In fact, it's recommended to name them differently to make import statements easier to read. 



You can have subpackages within the TaskPackage, so long as there is a top level module to import. Moreover, tasks that need variables must adhere to the same pattern of variables defined in [Variables](./variables.md). There is a `util` package with a `var_loader` module that has functions used to inject variables in the right order such as `build_task_vars`. This should be used wherever possible as it ensures all tasks load variables in the same manner. 

> Note: You may have to do some inserts to the syspath to get subpackages within a TaskPackage to import properly. 

Injecting Airflow Variables are slightly different as those may be specific to a task or not. Currently there is no shared way of doing this but you can look at the `install` task package to see how it uses those variables. 

## Dynamic Task Generation

A `TaskModule` is allowed to create multiple tasks, so long as the top level `dag.py` can successfully build the DAG. For instance, the `install.openshift` task module actually generates two tasks: `install_cluster` and `cleanup_cluster`. Dynamic Task generation makes sense if:

* You have multiple tasks that use the same configuration
* You have multiple tasks that are the same core executable with different configurations. (this is what the install package falls under)
## Adding the Task to the DAG

Your `TaskModule` needs to have a function returning an Airflow `Operator`. To add it to the DAG, you need to add code to the `dag.py` file to pull the Operator object in and add it to the DAG expression at the end of the file

## Tasks with Custom images

You can run a task with any image so long as it has airflow installed on it. It's recommended to roll custom images built on top of the base airflow image to 
ensure compatibility

You can change the image of a task by adding `executor_config` argument in the `Operator` you return. The `install` task does this as well.

# Real Life Task Examples

If you want to make quick sense of what tasks you will find in the current iteration, start here.

## `install`

Goal: Run an install to create a cluster.

The base class is at `install/openshift.py`, and is extended by each platform type, allowing specific configurations for each platform.

One important item to find here is the formatting of the install command (see 'scripts/install').

For example, when installing on a cloud platform, we look in `install/cloud/openshift.py` which formats the install command as follows:

```
bash_command=f"{constants.root_dag_dir}/scripts/install/cloud.sh -p {self.release.platform} -v {self.release.version} -j /tmp/{self.release_name}-{operation}-task.json -o {operation}",
```

which, in turn, contains the core of the install command: a playbook from `scale-ci-deploy`:

```
/home/airflow/.local/bin/ansible-playbook -vv -i inventory OCP-4.X/deploy-cluster.yml -e platform="$platform" --extra-vars "@${json_file}"
```

## `benchmark`

Goal: Configure a Benchmark task when building a DAG.

The `e2e.py` file, contains a function that creates a BashOperator instance with a `bash_command` argument that follows the logic below:

When the `custom_cmd` field is set

```
cmd = f"{constants.root_dag_dir}/scripts/run_benchmark.sh -c '{benchmark['custom_cmd']}'"

```
With the previous logic, `run_benchmark.sh` will run an arbitrary command.

Otherwise, `run_benchmarh.sh` will run an e2e-benchmarking based script based on the `workload` and `command` passed:
```
cmd = f"{constants.root_dag_dir}/scripts/run_benchmark.sh -w {benchmark['workload']} -c {benchmark['command']}",
```
