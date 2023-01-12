# Variables 

## Overview

Variables, generally speaking, are the configurations we pass through tasks either via JSON files stored in Git or directly in Airflow for secrets.

## Variable Hierarchy and Profiles

### Why do we need this?
We need to install and perf test Openshift in a variety of different environments and configurations that continues to grow. This easily creates a
"Variable Hell" where indepdendent configuration variables/files scale too fast to maintain. This can be mitigated by creating a variable hierarchy, where we can build a well-defined tree of variables that get applied in a specific order to prevent variable overload. 


> Note: This is a first pass and subject to change. Feel free to propose changes to this structure as it is not being functionally used yet


### How does it work? 
We model the variable hierarchy directly off of the way we define a `release` ([Read about releases](./manifest_and_releases.md)).

All `release` configurations should go into `config` and no where else. All default task configurations should go into `defaults.json` in the task package and no where else. This is a strict requirement and PRs breaking this pattern should not be merged. 

The `config` folder has a structure as follows:

```
config
└── $task
    └── $unique_task_config_name.json
```

For the install task specifically the structure is: 

```
config
└── $install
    └──$platform
        └── $unique_task_config_name.json
```

This is because install is the only task that is not platform agnostic. 

### Example: Finding config variables for a particular benchmark run
Some specific examples from the structure today looks like:
```
config
└── baremetal-benchmarks
    └── install-bench.json
└── benchmarks
    └── control-plane.json
└── install
    └── aws
        └── ovn.json
```

Three of these feilds (aws, ovn.json, and control-plane.json) are tied together in the manifest.yaml:
```
platforms:
  cloud:
    versions: ["4.11", "4.12"]
    providers: ["aws", "aws-arm", "gcp", "azure", "alibaba"]
    variants:
    - name: sdn-control-plane
      schedule: "0 12 * * 3"
      config:
        install: sdn.json
        benchmarks: control-plane.json
```
See [Manifests](./manifest_and_releases.md) for more detail around the Manifest.

If using the `util.var_loader` module functions to load task variables, this pattern will automatically load the task defaults as well as the release specific configurations and apply them properly. 

> Note: We require task developers to use the `util.var_loader.build_task_vars()` function to load your variables into your module. This has been tested to appropriately provide your module with a JSON-Compliant Dictionary with your configurations. 

## Airflow/Secret Variables

[See this page for more info on Secrets](./secrets.md)

## Task Variables

Task Variables are variables used in a specific instance of a task. As mentioned [here](#how-does-it-work), unique, often-used configuration of tasks should go in the `config` directory and follow the variable hierarchy. 

To avoid ambiguity in task configurations, task writers should add all possible variables to the `defaults.json` file **or** other documentation method that defines all of the variables (i.e. `defaults.md`)

Task writers are *required* to add a `defaults.json` file to their task with functional defaults. If there are no universal defaults, then the writer should add the configurations for all current releases that work with their task in the appropriate place and create a `defaults.json` file that is an empty json object `{}`. 

KISS still applies here. If a task needs no variables, then do none of this! If a task works on all releases with no specific configurations, don't create any configs inside the `config` folder!

# More on directories
## `install`
Each `platform` (or `provider` if platform==cloud) defined in the `manifest.yaml` is a unique directory here, where a JSON file can be used to specify variables unique to each cloud/provider/benchmark.  For example, AWS Instance Types may differ between a "small OVN" test (`install/aws/ovn.json`) and a "large OVN" test (`install/aws/ovn-large.json`).

## `benchmarks`
Each benchmark json contains the command, arguments, and variables to pass to the benchmark command, and is ultimately generates a fully-formed command via [e2e.py](dags/openshift_nightlies/tasks/benchmarks/e2e.py), to run [run_benchmark.sh](dags/openshift_nightlies/scripts/run_benchmark.sh).
From `run_benchmark.sh`, the corresponding workload from [e2e-benchmarking repo](https://github.com/cloud-bulldozer/e2e-benchmarking) is executed.