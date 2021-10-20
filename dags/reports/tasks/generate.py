from reports.pipeline import collect, enrich, index
from reports import util
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from elasticsearch import Elasticsearch
from prometheus_api_client import PrometheusConnect
import yaml

def build_reports(timestamp, config, es_url, thanos_url, grafana_url, target_index):
    es_client = Elasticsearch(es_url)
    thanos_client = PrometheusConnect(thanos_url, disable_ssl=True)
    clusters, docs = collect.get_clusters(es_client, timestamp, indices=config['searchIndices'])
    reports = []
    for cluster in clusters:
        benchmarks = collect.get_benchmarks_for_cluster(cluster['cluster_name'], docs, config['ignoreTags'])
        for benchmark in benchmarks:
            report = {
                **cluster,
                'report_type': 'podLatency',
                'metadata': benchmark['metadata'],
                "results": collect.get_benchmark_results(benchmark, es_client)
            }

            if report['results'] != {}:
                print(f"cluster {report['cluster_name']} has results")
                reports.append(report)
    
 
    for report in enrich.enrich_reports(reports, grafana_url, thanos_client, config):
        response = index.index_report(es_client, report, target_index)
        print(response) 

def get_task(dag, config):
    es_url = Variable.get('elasticsearch')
    grafana_url = Variable.get('grafana')
    thanos_url = Variable.get('thanos_querier_url')

    git_user = util.get_git_user()

    if git_user == "cloud-bulldozer":
        target_index = "ci-reports"
    else: 
        target_index = f"{git_user}-reports"
        config['searchIndices'].append(f"{git_user}_playground")


    task = PythonOperator(
        task_id='generate_report',
        dag=dag,
        python_callable=build_reports,
        op_kwargs={
            'timestamp': "now-14d/d",
            'config': config,
            'es_url': es_url,
            'thanos_url': thanos_url,
            'grafana_url': grafana_url,
            'target_index': target_index
        }
    )

