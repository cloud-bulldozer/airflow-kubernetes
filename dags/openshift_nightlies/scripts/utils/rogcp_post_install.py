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
import sys
import argparse
import subprocess
import os
import json

def _gcp_config(jsonfile):
    try:
      json_file = json.load(jsonfile)
    except Exception as err:
      print("Error occurred when reading %s file" % jsonfile)
      print(err)
      return 1
    my_env = os.environ.copy()
    my_env.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.path.realpath(json_file)
