import datetime
import statistics
from prometheus_api_client import PrometheusConnect, MetricRangeDataFrame, MetricsList
from metrics import util


def get_average_cpu_of_control_plane_apps(report, prom_client):
    result_set = {}

    start = util.parse_timestamp(report['metadata']['start_date'])
    end = util.parse_timestamp(report['metadata']['end_date'])
    cluster = report['cluster_name']
    metric = "container_cpu_usage_seconds_total"
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
    metric = "container_memory_working_set_bytes"
    labels = f'name!="", openshift_cluster_name="{cluster}", container!="POD",namespace=~"openshift-(etcd|oauth-apiserver|.*apiserver|ovn-kubernetes|sdn|ingress|authentication|.*controller-manager|.*scheduler|monitoring|image-registry|operator-lifecycle-manager)"'
    query = f'sum(container_memory_working_set_bytes{{{labels}}}) by (namespace)'
    metric_data = prom_client.custom_query_range(query=query, start_time=start, end_time=end, step=5)
    for series in metric_data:
        result_set[series['metric']['namespace']] = {
            "average": util.aggregate_metrics("average", series['values']),
            "max": util.aggregate_metrics("max", series['values'])
        }

    return result_set