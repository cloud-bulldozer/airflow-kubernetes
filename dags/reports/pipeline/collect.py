from reports.pipeline.results import kube_burner

def get_clusters(es_client, timestamp, indices=['perf_scale_ci']):
    query = {
        "query": {
            "range": {
                "timestamp":{
                    "gte": "now-1d/d"
                }
            }    
        }   
    }

    result = es_client.search(index=indices, body=query, size=10000)
    docs = [doc['_source'] for doc in result['hits']['hits']]
    unique_cluster_names = list(set([doc['cluster_name'] for doc in docs]))

    clusters = []

    for cluster in unique_cluster_names:
        for doc in docs:
            if doc['cluster_name'] == cluster:
                clusters.append({
                    "cluster_name": cluster,
                    "openshift_version": doc['cluster_version'],
                    "openshift_platform": doc['platform'],
                    "openshift_network_type": doc['network_type']
                })
                break
        print(f"got cluster {cluster}")

    return clusters


def get_benchmarks_for_cluster(cluster, docs, ignore_tags):
    return [{ "uuid": doc['uuid'], "build_tag": doc['build_tag'], "metadata": doc} for doc in docs if doc['cluster_name'] == cluster and doc['build_tag'] not in ignore_tags ]

def get_benchmark_results(benchmark, es_client):
    if "density" in benchmark['build_tag']:
        return kube_burner.get_results(benchmark, es_client)
    else:
        return {}