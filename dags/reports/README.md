# Report DAGs


The Report DAG is meant to orchestrate the analysis and report workflows for OpenShift Performance Results

Supported benchmark results:

* kube-burner

Supported metric profiles:

* control-plane 


# Workflow

### Step 0: The Raw Data
---

The report lifecycle starts with how the raw performance results are indexed. Currently we index all results based off a UUID with no cluster metadata attached to the raw results. In order to "enrich" the data later, we have configured the DAGs that run the benchmarks (in `dags/openshift_nightlies`) to also have indexer tasks that take snapshots of the cluster/task metadata and index it into a metadata index (currently `perf_scale_ci`) we will use to join and enrich the raw data later. The metadata has the following schema (pulled from `dags/openshift_nightlies/scripts/index.sh`). The uuid field is the one used in the benchmark run itself. 


```json
{
    "uuid" : "'$UUID'",
    "release_stream": "'$RELEASE_STREAM'",
    "platform": "'$platform'",
    "master_count": '$masters',
    "worker_count": '$workers',
    "infra_count": '$infra',
    "workload_count": '$workload',
    "master_type": "'$master_type'",
    "worker_type": "'$worker_type'",
    "infra_type": "'$infra_type'",
    "workload_type": "'$workload_type'",
    "total_count": '$all',
    "cluster_name": "'$cluster_name'",
    "cluster_version": "'$cluster_version'",
    "network_type": "'$network_type'",
    "build_tag": "'$task_id'",
    "node_name": "'$HOSTNAME'",
    "job_status": "'$state'",
    "build_url": "'$build_url'",
    "upstream_job": "'$dag_id'",
    "upstream_job_build": "'$dag_run_id'",
    "execution_date": "'$execution_date'",
    "job_duration": "'$duration'",
    "start_date": "'$start_date'", 
    "end_date": "'$end_date'", 
    "timestamp": "'$start_date'"
}

```


### Step 1: Get all the runs and benchmark results
---

The first step in the workflow is grab all the runs that ran in the last `n` days. That's pretty easy in ES:

```    query = {
        "query": {
            "range": {
                "timestamp":{
                    "gte": timestamp
                }
            }    
        }   
    }
```

After that we take these metadata docs and group them by the clusters to see what benchmarks each cluster had. After that we go through each of these benchmarks and grab the raw performance data from their respective indices. We can use the `build_tag` field to understand what type of benchmark was ran (i.e. if `build_tag == cluster-density` then we know it's a kube-burner benchmark and to query `ripsaw-kube-burner`). 

This generates the `results` field in a report doc. 

### Step 2: Get metrics from Thanos (optional) 
---

Since the metadata has the cluster name and all Thanos metrics have that label, we can query Thanos to get metrics specifically from that cluster. Moreover, since the metadata also has start/end times for the benchmarks, we can also get metrics from the specific cluster during the specific benchmark run. This makes querying thanos trivial as those are the only things needed to get any metric series you want. However, storing raw timeseries data in ES is not performant and unecessary given we have the raw metrics already in Thanos. Instead, this workflow will take an average of the metric series across the duration of the benchmark, as well as the max value it hit during the run (Note: this can be extended) 

This generates the `metrics` field in a report doc. 


### Step 3: Generate Links (optional)
---

For some benchmarks that we know users have a high propensity for looking at the raw metrics, we pre-compile links to benchmark-specific dashboards that are backed by Thanos (so raw metrics are available) and pre-configured to query metrics for the desired cluster + time range. This allows us to "join" the raw metrics to the data without having to actually store the timeseries data in ES. 

This generates the `links` field in a report doc. 

### Step 4: Add the metadata back to the report
---

The last step is to simply add the metadata doc used in Step 0 back to the report under the `metadata` field. This lets users query for results off of any of that metadata, including uuid, cluster name, platform, etc. This also powers visualizations off of those fields as wel. 


## Report Schema

Ultimately the report schema is fairly lightweight. The schema makes no assumptions on the structure of benchmark results, metrics, or extra links. It merely defines where that type of data should go. Stricter schemas should be applied on a per-benchmark basis as visualizations require them. 

The final report schema looks something like this:


```json
{
    "openshift_cluster_name": "string",
    "openshift_cluster_version": "string",
    "openshift_network_type": "string",
    "openshift_platform": "string", 
    "metadata": {},
    "results": {},
    "metrics": {},
    "links": {}
}



```