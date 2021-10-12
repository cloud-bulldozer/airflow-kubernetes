import datetime
from reports.pipeline.metrics import control_plane

def generate_dashboard_links(report, grafana_url, dashboards):
    links = {}
    time_range_start = int(datetime.datetime.strptime(report['metadata']['start_date'], "%Y-%m-%dT%H:%M:%S.%f%z").timestamp()) * 1000
    time_range_end = int(datetime.datetime.strptime(report['metadata']['end_date'], "%Y-%m-%dT%H:%M:%S.%f%z").timestamp()) * 1000
    time_range = f"from={time_range_start}&to={time_range_end}"
    query_labels = f"var-cluster_name={report['cluster_name']}"
    for key, dashboard in dashboards.items():
        links[key] = f"{grafana_url}/d/{dashboard['id']}/{dashboard['name']}?orgId=1&{time_range}&{query_labels}"
    
    return links

def enrich_reports(reports, grafana_url, prom_client, config):
    for report in reports:
        report['timestamp'] = datetime.datetime.utcnow()
        report['links'] = generate_dashboard_links(report, grafana_url, config['dashboards']) 
        if report['openshift_platform'] == "AWS":
            report['metrics'] = {
                "podCPU": control_plane.get_average_cpu_of_control_plane_apps(report, prom_client),
                "podMemory": control_plane.get_average_memory_of_control_plane_apps(report, prom_client)
            }
        yield report