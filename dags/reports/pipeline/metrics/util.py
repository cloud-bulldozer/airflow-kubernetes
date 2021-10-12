import datetime

def parse_timestamp(timestamp):
    return datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")

def aggregate_metrics(operation, metric_data):
    if operation == "average":
        return statistics.mean(float(datapoint[1]) for datapoint in metric_data)
    elif operation == "max":
        return max(float(datapoint[1]) for datapoint in metric_data)