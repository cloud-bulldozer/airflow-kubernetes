# Variables 

## Overview

Variables, generally speaking, are the configurations we pass through tasks either via JSON files stored in Git or directly in Airflow for secrets.

## Variable Hierarchy and Profiles


We need to install and perf test Openshift in a variety of different environments and configurations that continues to grow. This easily creates a
"Variable Hell" where indepdendent configuration variables/files scale too fast to maintain. This can be mitigated by creating a variable hierarchy, where we can build a well-defined tree of variables that get applied in a specific order to prevent variable overload. 


> Note: This is a first pass and subject to change. Feel free to propose changes to this structure as it is not being functionally used yet

Generally speaking, this project attempts to mitigate this problem by slicing variables at the `version` and `platform` level, as well as creating a third `profile` level. 

1. `version` refers to the openshift release (i.e. stable)
2. `platform` refers to the platform openshift is being installed on (i.e. aws)
3. `profile` refers to a specific configuration within that release+platform (i.e. ovn)


The combination of these three arguments defines a unique `release` within the `manifest.yaml`


#### Airflow Variables

Airflow variables can be defined inside Airflow and pulled through the Airflow SDK. You can parameterize those as well so long as they are parameterized off of 1 or more of the above 3 variables. Variables containing sensitive information should be stored here. 

#### Task Variables

Task Variables should be defined in accordance with the variable hierarchy, although tasks can have their own defaults that sit atop all profiles. 

A good example is the install task:

```
releases
├── next
└── stable
    └── aws
        └── default
            └── install.json
```

KISS still applies here. If a task has no reason to split the variables then there is no reason to write the logic to do so. 