# Secret Variables

While storing the Task configurations in Git is powerful, it's biggest gap is that it's a terrible place to store configurations you wish to keep secret. This could include things such as:

* Cloud Account Credentials
* Username/Passwords
* SSH Keys

To resolve this, Airflow lets you [define variables](https://airflow.apache.org/docs/apache-airflow/stable/howto/variable.html) in the UI/CLI and pulled through the Airflow SDK. 



# Sailplane Vault

For users leveraging the `playground` or `tenant` mode of installation benefit from the fact that Airflow instances created with those modes are auto-wired to connect to our [Vault](https://www.vaultproject.io/) instance. This ensures Airflow will work OOTB as our Vault has all of the required variables defined in it. 

## Overriding Vault Variables

If Airflow is connected to a Vault instance, those variables will take precendence over any defined locally within Airflow. In order to allow users to override the variables with their own configurations, users can create a singular `overrides` variable in Airflow that is a JSON blob with mappings of the variable key to the new desired value. 

Example `overrides` variable:

```json

{
    "ansible_orchestrator": {
        "orchestration_host": "my_custom_host",
        "orchestration_user": "my_custom_user"
    },
    "elasticsearch": "my_custom_elastic_url"
}

```





# Supported Variables

Currently the code pulls the following variables. Our Vault also has default values for them. 

---
Key: `ansible_orchestrator`

Type: JSON

Description: Ansible orchestrator to run playbooks

Used by: install, cleanup 

Platforms: Cloud (all providers)

Schema:

```json
    {
        "orchestration_host": "string",
        "orchestration_user": "string"
    }
```

---
Key: `aws_creds`

Type: JSON

Description: AWS Credentials for account to install Openshift Clusters into

Used by: install, cleanup 

Platforms: Cloud (aws)

Schema:

```json
    { 
        "aws_access_key_id": "string",
        "aws_profile": "string",
        "aws_region_for_openshift": "string",
        "aws_secret_access_key": "string" 
    }
```

---
Key: `azure_creds`

Type: JSON

Description: Azure Credentials for account to install Openshift Clusters into

Used by: install, cleanup 

Platforms: Cloud (azure)

Schema:

```json
    { 
        "azure_base_domain_resource_group_name": "string",
        "azure_region": "string",
        "azure_service_principal_client_id": "string",
        "azure_service_principal_client_secret": "string",
        "azure_subscription_id": "string",
        "azure_tenant_id": "string"

    }
```

---
Key: `baremetal_openshift_install_config`

Type: JSON

Description: Common Baremetal Install Configs

Used by: install, cleanup 

Platforms: Baremetal

Schema: N/A

---
Key: `elasticsearch`

Type: string

Description: ES Server to index results to. 

Used by: install, benchmarks, cleanup, indexers

Platforms: All

Schema: Fully qualified ES URL such as `https://$user:$pass@hostname:$port`

---
Key: `gcp_creds`

Type: JSON

Description: GCP Credentials for account to install Openshift Clusters into

Used by: install, cleanup

Platforms: Cloud (gcp)

Schema:

```json
{
    "gcp_auth_key_file": "string",
    "gcp_project": "string",
    "gcp_region": "string",
    "gcp_service_account": "string",
    "gcp_service_account_email": "string"
}

```

---
Key: `openshift_install_config`

Type: JSON

Description: Common openshift install configurations that aren't configurable

Used by: install, cleanup

Platforms: Cloud (all)

Schema: N/A


---
Key: `openstack_creds`

Type: JSON

Description: Openstack credentials for installs

Used by: install, cleanup

Platforms: Openstack

Schema: N/A

---
Key: `release_stream_base_url`

Type: string

Description: Upstream OpenShift Release Stream API used to grab the latest nightly build of a given version. 

Used by: install, cleanup

Platforms: Cloud (all), Openstack

Schema: Fully qualified URL

---
Key: `snappy_creds`

Type: JSON

Description: Credentials for snappy server that houses cluster artifacts we wish to keep after the cluster is destroyed

Used by: scale_ci_diagnosis

Platforms: All

Schema:

```json
{
    "username": "string",
    "server": "string",
    "password": "string"
}

```