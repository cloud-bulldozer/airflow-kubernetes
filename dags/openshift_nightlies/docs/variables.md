# Variables 

## Overview

Variables, generally speaking, are the configurations we pass through tasks either via JSON files stored in Git or directly in Airflow for secrets.

## Variable Hierarchy and Profiles

### Why do we need this?
We need to install and perf test Openshift in a variety of different environments and configurations that continues to grow. This easily creates a
"Variable Hell" where indepdendent configuration variables/files scale too fast to maintain. This can be mitigated by creating a variable hierarchy, where we can build a well-defined tree of variables that get applied in a specific order to prevent variable overload. 


> Note: This is a first pass and subject to change. Feel free to propose changes to this structure as it is not being functionally used yet


### How does it work? 
We model the variable hierarchy directly off of the way we define a `release` ([Read about releases](./manifest_and_release.md)).

All `release` configurations should go into `releases` and no where else. All default task configurations should go into `defaults.json` in the task package and no where else. This is a strict requirement and PRs breaking this pattern should not be merged. 

The `releases` folder has a structure as follows:

```
releases
└── $version
    └── $platform
        └── $profile
            └── $task.json
```

If using the `util.var_loader` module functions to load task variables, this pattern will automatically load the task defaults as well as the release specific configurations and apply them properly. 

> Note: We *highly* recommend task developers to use the `util.var_loader.build_task_vars()` function to load your variables into your module. This has been tested to appropriately provide your module with a JSON-Compliant Dictionary with your configurations. 

## Airflow/Secret Variables

Airflow variables can be defined inside Airflow and pulled through the Airflow SDK. You can parameterize those as well so long as they are parameterized off of 1 or more of the above 3 variables. Variables containing sensitive information should be stored here. 

> TODO: We need to have a more robust way of defining Secret Variables. For now, please ensure you aren't using a variable name already being used in another DAG. And try to make yours unique enough to not cause future conflicts. 

## Task Variables

Task Variables are variables used in a specific instance of a task. As mentioned [here](#how-does-it-work), release-specific configuration of tasks should go in the `releases` directory and follow the variable hierarchy. 

To avoid ambiguity in task configurations, task writers should add all possible variables to the `defaults.json` file **or** other documentation method that defines all of the variables (i.e. `defaults.md`)

Task writers are *required* to add a `defaults.json` file to their task with functional defaults. If there are no universal defaults, then the writer should add the configurations for all current releases that work with their task in the appropriate place and create a `defaults.json` file that is an empty json object `{}`. 

KISS still applies here. If a task needs no variables, then do none of this! If a task works on all releases with no specific configurations, don't create any configs inside the `releases` folder!