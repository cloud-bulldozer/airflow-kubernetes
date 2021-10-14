import datetime
import statistics
from reports.pipeline.metrics import util


def get_average_cpu_of_control_plane_apps(report, prom_client):
    result_set = {}

    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    labels = f'name!="", openshift_cluster_name="{cluster}", container!="POD",namespace=~"openshift-(etcd|oauth-apiserver|.*apiserver|ovn-kubernetes|sdn|ingress|authentication|.*controller-manager|.*scheduler|monitoring|image-registry|operator-lifecycle-manager)"'
    query = f'sum(irate(container_cpu_usage_seconds_total{{{labels}}}[2m])) by (namespace)'
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    for series in metric_data:
        result_set[series['metric']['namespace']] = {
            "average": util.aggregate_metrics("average", series['values']),
            "max": util.aggregate_metrics("max", series['values'])
        }

    return result_set

def get_average_memory_of_control_plane_apps(report, prom_client):
    result_set = {}

    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    labels = f'name!="", openshift_cluster_name="{cluster}", container!="POD",namespace=~"openshift-(etcd|oauth-apiserver|.*apiserver|ovn-kubernetes|sdn|ingress|authentication|.*controller-manager|.*scheduler|monitoring|image-registry|operator-lifecycle-manager)"'
    query = f'sum(container_memory_working_set_bytes{{{labels}}}) by (namespace)'
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    for series in metric_data:
        result_set[series['metric']['namespace']] = {
            "average": util.aggregate_metrics("average", series['values']),
            "max": util.aggregate_metrics("max", series['values'])
        }

    return result_set



def get_masters(report, prom_client):
    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    labels = f'openshift_cluster_name="{cluster}", role="master"'
    query = f'sum(kube_node_role{{{labels}}}) by (node)'
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    return [series['metric']['node'] for series in metric_data]

def get_average_cpu_of_master_nodes(report, prom_client):
    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    master_nodes = get_masters(report, prom_client)
    labels = f'openshift_cluster_name="{cluster}", instance=~"{"|".join(master_nodes)}", mode!="idle"'
    query = f'sum(irate(node_cpu_seconds_total{{{labels}}}[2m])) by (instance)'
    print(query)
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    if len(metric_data) != 0:
        return {
            "average": statistics.mean([util.aggregate_metrics("average", series['values']) for series in metric_data])
        }
    else:
        return {}

def get_average_available_memory_of_master_nodes(report, prom_client):
    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    master_nodes = get_masters(report, prom_client)
    labels = f'openshift_cluster_name="{cluster}", instance=~"{"|".join(master_nodes)}", mode!="idle"'
    query = f'avg(node_memory_MemTotal_bytes{{{labels}}}) by (instance) - avg(node_memory_MemAvailable_bytes{{{labels}}}) by (instance) '
    print(query)
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    if len(metric_data) != 0:
        return {
            "average": statistics.mean([util.aggregate_metrics("average", series['values']) for series in metric_data])
        }
    else:
        return {}