#!/usr/bin/env python
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

from kubernetes import client, config
from openshift.dynamic import DynamicClient
from google.oauth2 import service_account
import sys
import argparse
import subprocess
import datetime
import os
import json

def _gcp_config(jsonfile):
    try:
      credentials = service_account.Credentials.from_service_account_file(jsonfile)
      my_env = os.environ.copy()
      return my_env
    except Exception as err:
      print("Error occurred when reading %s file" % jsonfile)
      print(err)
      return 1


def _create_workload_machines(cluster_name, my_env):
    ocm_create_worker_cmd = ["ocm create machinepool -c " +cluster_name +"\
        --instance-type custom-16-65536 --labels \
        'node-role.kubernetes.io/workload='\
        --taints 'role=workload:NoSchedule' --replicas 3 workload"]
    print(ocm_create_worker_cmd)
    process = subprocess.Popen(ocm_create_worker_cmd, stdout=subprocess.PIPE,\
        stderr=subprocess.PIPE, shell=True, env=my_env)
    stdout, stderr = process.communicate()
    print("creating machine workload")
    print(stdout)
    print(stderr)
    return cluster_name

def _extend_ocm_lifetime(cluster_name, my_env):
    timestamp = datetime.datetime.utcnow() + datetime.timedelta(days=1)
    tomorrow = timestamp.strftime("%Y-%m-%dT%H:%M:%S%ZZ")
    ocm_extend_lifetime_command = ["ocm patch /api/clusters_mgmt/v1/clusters/" + cluster_name \
        + "\'{\"expiration_timestamp\": \"" + tomorrow + "\"}\'"]
    print(ocm_extend_lifetime_command)
    process = subprocess.Popen(ocm_extend_lifetime_command, stdout=subprocess.PIPE, \
        stderr=subprocess.PIPE, shell=True, env=my_env)
    stdout, stderr = process.communicate()
    print("extending the lifetime of cluster")
    print(stdout)
    print(stderr)

def _get_gcp_network(cluster_name, my_env):
    get_gcp_network_cmd = ["gcloud compute networks list --filter="name~'^cluster_name'" | awk 'FNR==2 {print $1}"
    print(get_gcp_network_cmd)
    process = subprocess.Popen(get_gcp_network_cmd, stdout=subprocess.PIPE, \
        stderr=subprocess.PIPE, shell=True, env=my_env)
    stdout, stderr = process.communicate()
    network = stdout.decode('utf-8')
    return network

def _gcp_network_rules(cluster_name, my_env):
    network = _get_gcp_network(cluster_name)
    gcp_networking_rules = ["gcloud compute firewall-rules create $CLUSTERNAME-icmp --network $CLUSTERNAME-network --priority 101 --description 'scale-ci allow icmp' --allow icmp",
                            "gcloud compute firewall-rules create $CLUSTERNAME-ssh --network $CLUSTERNAME-network --direction INGRESS --priority 102 --description 'scale-ci allow ssh' --allow tcp:22",
                            "gcloud compute firewall-rules create $CLUSTERNAME-pbench --network $CLUSTERNAME-network --direction INGRESS --priority 103 --description 'scale-ci allow pbench-agents' --allow tcp:2022",
                            "gcloud compute firewall-rules create CLUSTERNAME-net --network $CLUSTERNAME-network --direction INGRESS --priority 104 --description 'scale-ci allow tcp,udp network tests' --rules tcp:20000-20109,udp:20000-20109 --action allow",
                            "gcloud compute firewall-rules create $CLUSTERNAME-hostnet --network $CLUSTERNAME-network --priority 105 --description 'scale-ci allow tcp,udp hostnetwork tests' --rules tcp:32768-60999,udp:32768-60999 --action allow"]

def _main():
    parser = argparse.ArgumentParser(description="ROGCP Post install configuration for PerfScale CI")
    parser.add_argument(
        '--incluster',
        default="false",
        type=str,
        help='Is this running from a pod within the cluster [true|false]')
    parser.add_argument(
        '--kubeconfig',
        help='Optional kubeconfig location. Incluster cannot be true')
    parser.add_argument(
        '--jsonfile',
        help='Optional configuration file including all the dag vars')
    args = parser.parse_args()

    if args.incluster.lower() == "true":
        config.load_incluster_config()
        k8s_config = client.Configuration()
        k8s_client = client.api_client.ApiClient(configuration=k8s_config)
    elif args.kubeconfig:
        k8s_client = config.new_client_from_config(args.kubeconfig)
    else:
        k8s_client = config.new_client_from_config()

    dyn_client = DynamicClient(k8s_client)
    nodes = dyn_client.resources.get(api_version='v1', kind='Node')

    if args.kubeconfig:
        cmd = ["oc get infrastructures.config.openshift.io cluster -o jsonpath={.status.infrastructureName} --kubeconfig " + args.kubeconfig]
    else:
        cmd = ["oc get infrastructures.config.openshift.io cluster -o jsonpath={.status.infrastructureName}"]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout,stderr = process.communicate()
    my_env = _gcp_config(json_file)
    clustername = stdout.decode("utf-8")
    _create_workload_machines(cluster_name, my_env)
    _extend_ocm_lifetime(cluster_name, my_env)
    _gcp_network_rules(cluster_name, my_env)
