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