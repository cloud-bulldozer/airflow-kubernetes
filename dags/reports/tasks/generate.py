from pipeline import collect, enrich, index
from pipeline.metrics import control_plane
from pipeline.results

def build_reports(es_client, timestamp, config):
    clusters = collect.get_clusters(es_client, timestamp)
    for cluster in clusters:
        benchmarks = collect.get_benchmarks_for_cluster(cluster['cluster_name'], docs)
        for benchmark in benchmarks:
            report = {
                **cluster,
                'report_type': 'podLatency',
                'metadata': benchmark['metadata'],
                "results": collect.get_benchmark_results(benchmark)
            }

            if report['results'] != {}:
                print(f"cluster {report['cluster_name']} has results")
                reports.append(report)
    
    enriched_reports
    index.index_reports(es_client, reports, target_index)

def get_task():
    pass