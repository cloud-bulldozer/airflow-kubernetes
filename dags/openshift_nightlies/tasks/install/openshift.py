import json
from airflow.operators.bash_operator import BashOperator
from airflow.models import Variable

# Defines Tasks for installation of Openshift Clusters

class OpenshiftInstaller():
    def __init__(self, dag, platform, version, profile, vars): 

        # Which Image do these tasks use
        self.exec_config = {
            "KubernetesExecutor": {
                "image": "quay.io/keithwhitley4/airflow-ansible:new-ansible-3"
            }
        }

        # General DAG Configuration 
        self.dag = dag
        self.platform = platform # e.g. aws
        self.version = version # e.g. stable/.next/.future
        self.profile = profile # e.g. default/ovn
        
        
        # Specific Task Configuration
        self.vars = vars


        # Airflow Variables
        self.ansible_orchestrator = Variable.get("ansible_orchestrator", deserialize_json=True)
        self.version_secrets = Variable.get(f"openshift_install_{self.version}", deserialize_json=True)
        self.aws_creds = Variable.get("aws_creds", deserialize_json=True)
       
    def get_install_task(self):
        return _get_task(operation="install")

    def get_cleanup_task(self):
        # trigger_rule = "all_done" means this task will run when every other task has finished, whether it fails or succeededs
        return _get_task(self, operation="cleanup", trigger_rule="all_done")
    
    # Create Airflow Task for Install/Cleanup steps
    def _get_task(self, operation="install", trigger_rule="all_success"):
        playbook_operations = Variable.get(f"playbook_{operation}", deserialize_json=True)

        # Merge all variables, prioritizing Airflow Secrets over git based vars
        config = {**self.vars, **self.ansible_orchestrator, **self.version_secrets, **self.aws_creds, **playbook_operations}

        # Required Environment Variables for Install script
        env = {
            "SSHKEY_TOKEN": config['sshkey_token'],
            "ORCHESTRATION_HOST": config['orchestration_host']
        }
        

        # Dump all vars to json file for Ansible to pick up
        with open(f"/home/airflow/{self.operation}_task.json", 'w') as json_file:
            json.dump(self.vars, json_file, sort_keys=True, indent=4)

        return BashOperator(
            task_id=f"{self.operation}_rhos_{self.version}_{self.platform}",
            depends_on_past=False,
            bash_command=f"/opt/airflow/dags/repo/dags/openshift_nightlies/scripts/install_cluster.sh -p {self.platform} -v 4 -j /home/airflow/{self.operation}_task.json",
            retries=0,
            dag=self.dag,
            trigger_rule=self.trigger_rule,
            executor_config=self.exec_config,
            env=env
        )