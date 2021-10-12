from reports.pipeline import collect, enrich, index
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from elasticsearch import Elasticsearch
from prometheus_api_client import PrometheusConnect
import yaml

def build_reports(timestamp, config, es_client, thanos_client, grafana_url):
    clusters = collect.get_clusters(es_client, timestamp)
    for cluster in clusters:
        benchmarks = collect.get_benchmarks_for_cluster(cluster['cluster_name'], docs, config['ignoreTags'])
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
    
 
    for report in enrich.enrich_reports(reports):
        response = index.index_report(es_client, report, config['reportIndex'])
        print(response) 

def get_task(dag, config):
    es_client = Elasticsearch(Variable.get('elasticsearch'))
    grafana_url = Variable.get('grafana')
    thanos_client = PrometheusConnect(url=Variable.get('thanos_querier_url'), disable_ssl=True)
    task = PythonOperator(
        task_id='generate_report',
        dag=dag,
        python_callable=build_reports,
        op_kwargs={
            'timestamp': "",
            'config': config,
            'es_client': es_client,
            'thanos_client': thanos_client,
            'grafana_url': grafana_url
        }
    )

