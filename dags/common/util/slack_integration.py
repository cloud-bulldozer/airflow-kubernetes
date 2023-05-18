from airflow.hooks.base import BaseHook
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
from common.util import var_loader

SLACK_CONN_ID = 'slack'


def alert_members(context):

    dag_id = context.get('task_instance').dag_id
    if "openstack" in dag_id:
        members = "@Masco"
    else:
        members = "@perfscale-team"
    return members


def get_hyperlink(context):
    link = "<{0}|Dag Link>".format(context.get('task_instance').log_url)
    return str(link)


def task_fail_slack_alert(context):
    slack_webhook_token = BaseHook.get_connection(SLACK_CONN_ID).password
    ti = context.get('task_instance')
    if context.get('task_instance').task_id == "final_status":
        failed_tasks = ti.xcom_pull(key="failed_tasks", task_ids="final_status")
        print(f"Failed tasks: {failed_tasks}")
    else:
        return
    # If the git user is not cloud-bulldozer, skip pushing message to slack
    if var_loader.get_git_user() != "cloud-bulldozer":
        return

    slack_msg = """
            :red_circle: DAG Failed {mem}
            *Task*: {task}
            *Dag*: {dag}
            *Execution Time*: {exec_date}
            *Log Url*: {log_url}
            *Failed tasks*: {failed_tasks}
            """.format(
            task=context.get('task_instance').task_id,
            dag=context.get('task_instance').dag_id,
            mem=alert_members(context),
            exec_date=context.get('execution_date'),
            log_url=get_hyperlink(context),
            failed_tasks=failed_tasks
        )
    failed_alert = SlackWebhookOperator(
        task_id='slack_test',
        http_conn_id='slack',
        webhook_token=slack_webhook_token,
        message=slack_msg,
        username='airflow',
        link_names=True)
    return failed_alert.execute(context=context)
