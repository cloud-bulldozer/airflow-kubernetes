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

import sys
import argparse
import subprocess
import os
import json

# Make aws related config changes such as security group rules etc
def _aws_config(clustername,jsonfile,kubeconfig):
    try:
        json_file = json.load(open(jsonfile))
    except Exception as err:
        print("Error occurred when reading %s file" % jsonfile)
        print(err)
        return 1
    my_env = os.environ.copy()
    my_env['AWS_ACCESS_KEY_ID'] = json_file['aws_access_key_id']
    my_env['AWS_SECRET_ACCESS_KEY'] = json_file['aws_secret_access_key']
    my_env['AWS_DEFAULT_REGION'] = json_file['aws_region']
    if "rosa_hcp" in json_file and json_file["rosa_hcp"] == "true":
        clustername_check_cmd = ["oc get infrastructures.config.openshift.io cluster -o json --kubeconfig " + kubeconfig + " | jq -r '.status.platformStatus.aws.resourceTags[] | select( .key == \"api.openshift.com/name\" ).value'"]
        print(clustername_check_cmd)
        process = subprocess.Popen(clustername_check_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, env=my_env)
        stdout,stderr = process.communicate()
        clustername = stdout.decode("utf-8").replace('\n','').replace(' ','')     
    vpc_cmd = ["aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PrivateIpAddress,PublicIpAddress, PrivateDnsName, VpcId]' --output text | column -t | grep " + clustername + "| awk '{print $7}' | grep -v '^$' | sort -u"]
    print(vpc_cmd)
    process = subprocess.Popen(vpc_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, env=my_env)
    stdout,stderr = process.communicate()
    print("VPC:")
    print(stdout)
    print(stderr)
    cluster_vpc = stdout.decode("utf-8").replace('\n','').replace(' ','')
    sec_grp_cmd = ["aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=" + cluster_vpc + "\" --output json | jq .SecurityGroups[].GroupId"]
    print(sec_grp_cmd)
    process = subprocess.Popen(sec_grp_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, env=my_env)
    stdout,stderr = process.communicate()
    print("Security Groups:")
    print(stdout)
    print(stderr)
    sec_group = stdout.decode("utf-8").replace(' ','').replace('"','').replace('\n',' ')

    sec_group_list = list(sec_group.split(" "))
    print(sec_group_list)

    sec_group_cmds = ["aws ec2 authorize-security-group-ingress --group-id ITEM --protocol tcp --port 22 --cidr 0.0.0.0/0",
                      "aws ec2 authorize-security-group-ingress --group-id ITEM --protocol tcp --port 2022 --cidr 0.0.0.0/0",
                      "aws ec2 authorize-security-group-ingress --group-id ITEM --protocol tcp --port 20000-31000 --cidr 0.0.0.0/0",
                      "aws ec2 authorize-security-group-ingress --group-id ITEM --protocol udp --port 20000-31000 --cidr 0.0.0.0/0",
                      "aws ec2 authorize-security-group-ingress --group-id ITEM --protocol tcp --port 32768-60999 --cidr 0.0.0.0/0",
                      "aws ec2 authorize-security-group-ingress --group-id ITEM --protocol udp --port 32768-60999 --cidr 0.0.0.0/0"]
    for item in sec_group_list:
        if item == "":
            return
        else:
            for cmnd in sec_group_cmds:
                my_cmd = cmnd.replace('ITEM',item)
                print(my_cmd)
                try:
                    process = subprocess.Popen(my_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, env=my_env)
                    stdout,stderr = process.communicate()
                except Exception as err:
                    print("Error occurred when setting security groups")
                    print(err)
                print("Security Groups Authorize")
                print(stdout)
                print(stderr)

def main():
    parser = argparse.ArgumentParser(description="ROSA Post install configuration for PerfScale CI")
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

    if args.kubeconfig:
        cmd = ["oc get infrastructures.config.openshift.io cluster -o jsonpath={.status.infrastructureName} --kubeconfig " + args.kubeconfig]
    else:
        cmd = ["oc get infrastructures.config.openshift.io cluster -o jsonpath={.status.infrastructureName}"]

    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout,stderr = process.communicate()
    clustername = stdout.decode("utf-8")

    # AWS configuration
    _aws_config(clustername,args.jsonfile,args.kubeconfig)


if __name__ == '__main__':
    sys.exit(main())
