def get_results(benchmark, es_client):
    pod_latencies = get_pod_latency_results(benchmark, es_client)
    job_summary = get_job_summary(benchmark, es_client)

    return {**pod_latencies, **job_summary}


def get_pod_latency_results(benchmark, es_client):
    query = {
        "query":{ 
            "query_string": {
                "query": f'uuid:"{benchmark["uuid"]}" AND (metricName:"podLatencyQuantilesMeasurement")'
            }
        }
    }
    index = 'ripsaw-kube-burner'
    query_results = es_client.search(index='ripsaw-*', body=query, size=10000)
    perf_data = {doc['_source']['quantileName']: doc['_source'] for doc in query_results['hits']['hits']}
    
    return perf_data

def get_job_summary(benchmark, es_client):
    query = {
        "query": {
            "query_string": {
                "query": f'uuid:"{benchmark["uuid"]}" AND (metricName:"jobSummary")'
            }
        }
    }
    index = 'ripsaw-kube-burner'
    query_results = es_client.search(index='ripsaw-*', body=query, size=10000)
    perf_data = {"jobSummary": doc['_source'] for doc in query_results['hits']['hits']}
    
    return perf_data