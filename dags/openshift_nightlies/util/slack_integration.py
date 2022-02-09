from airflow.hooks.base import BaseHook
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
import logging
from os import environ

SLACK_CONN_ID = 'slack'

# Used to get the git user for the repo the dags live in. 
def get_git_user():
    git_repo = environ['GIT_REPO']
    git_path = git_repo.split("https://github.com/")[1]
    git_user = git_path.split('/')[0]
    return git_user.lower()


def alert_members(context):
    if "rosa" in context.get('task_instance').dag_id or "rogcp" in context.get('task_instance').dag_id or "-aro-" in context.get('task_instance').dag_id:
        members=" @perfscale-managed-services-team" 
    elif "aws" in context.get('task_instance').dag_id or "azure" in context.get('task_instance').dag_id or "-gcp-" in context.get('task_instance').dag_id or "baremetal" in context.get('task_instance').dag_id:
        members=" @perfscale-core-team"
    elif "openstack" in context.get('task_instance').dag_id:
        members=" @asagtani @masco"
    else:
        members=""
    return members            


def task_fail_slack_alert(context):
    slack_webhook_token = BaseHook.get_connection(SLACK_CONN_ID).password
    if get_git_user() != "cloud-bulldozer":
        print("Task Failed")
        return
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
            log_url=context.get('task_instance').log_url,
        )
    failed_alert = SlackWebhookOperator(
        task_id='slack_test',
        http_conn_id='slack',
        webhook_token=slack_webhook_token,
        message=slack_msg,
        username='airflow',
        link_names=True)
    return failed_alert.execute(context=context)