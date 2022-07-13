from airflow.hooks.base import BaseHook
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
import logging
from os import environ
from common.util import var_loader

SLACK_CONN_ID = 'slack'

def alert_members(context):

    dag_id = context.get('task_instance').dag_id 
    managed_services_terms = [ "rosa", "rogcp", "-aro-" ] 
    perf_core_terms = ["aws", "azure", "-gcp-","baremetal"]

    if any(term in dag_id for term in managed_services_terms):
        members = " @perfscale-managed-services-team"
    elif any(term in dag_id for term in perf_core_terms):
        members=" @perfscale-core-team"
    elif "openstack" in dag_id:
        members=" @asagtani @masco"
    else:
        members=""
    return members    

def get_hyperlink(context):
    link= "<{0}|Dag Link>".format(context.get('task_instance').log_url)
    return str(link)        


def task_fail_slack_alert(context):
    slack_webhook_token = BaseHook.get_connection(SLACK_CONN_ID).password
    if var_loader.get_git_user() != "cloud-bulldozer":
        print("Task Failed")
        return
    if context.get('task_instance').task_id != "final_status":
        print(context.get('task_instance').task_id,"Task failed")
        return
   
    slack_msg = """
            :red_circle: DAG Failed {mem} 
            *Task*: {task}  
            *Dag*: {dag} 
            *Execution Time*: {exec_date}  
            *Log Url*: {log_url} 
            """.format(
            task=context.get('task_instance').task_id,
            dag=context.get('task_instance').dag_id,
            mem=alert_members(context),
            ti=context.get('task_instance'),
            exec_date=context.get('execution_date'),
            log_url=get_hyperlink(context),
        )
    failed_alert = SlackWebhookOperator(
        task_id='slack_test',
        http_conn_id='slack',
        webhook_token=slack_webhook_token,
        message=slack_msg,
        username='airflow',
        link_names=True)
    return failed_alert.execute(context=context)
