from airflow.hooks.base import BaseHook
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
import logging
from os import environ
from openshift_nightlies.util import var_loader

SLACK_CONN_ID = 'slack'

def alert_members(context):
    if "rosa" in context.get('task_instance').dag_id or "rogcp" in context.get('task_instance').dag_id or "-aro-" in context.get('task_instance').dag_id:
        members=" @perfscale-managed-services-team" 
    elif "awsf" in context.get('task_instance').dag_id or "azure" in context.get('task_instance').dag_id or "-gcp-" in context.get('task_instance').dag_id or "baremetal" in context.get('task_instance').dag_id:
        members=" @perfscale-core-team"
    elif "openstack" in context.get('task_instance').dag_id:
        members=" @asagtani @masco"
    else:
        members=""
    return members    

def get_hyperlink(context):
    link= '{"blocks":[{"type": "section","text":{"type": "mrkdwn","text": "<{0}|Dag Link>"}}]}'.format(context.get('task_instance').log_url)
    return str(link)        


def task_fail_slack_alert(context):
    slack_webhook_token = BaseHook.get_connection(SLACK_CONN_ID).password
    #if var_loader.get_git_user() != "cloud-bulldozer":
    #    print("Task Failed")
    #    return
    if "index" in context.get('task_instance').task_id:
        print("Index Task Failed")
        return
   
    slack_msg = """
            :red_circle: Task Failed {mem} 
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