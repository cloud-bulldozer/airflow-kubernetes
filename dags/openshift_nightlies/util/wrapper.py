from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.python_operator import BranchPythonOperator

# This Class wraps a task with a conditional and will skip the task if the conditional is true
class ConditionalTask():
    def __init__(self, dag, condition, task):
        self.dag = dag
        self.condition = condition
        self.task = task 

    def _get_task(self):
        if condition: 
            return self.task.task_id
        else:
            return DummyOperator(dag=self.dag, task_id=f"skip_{self.task.task_id}").task_id

    def get_task(self):
        return BranchPythonOperator(
            dag=self.dag,
            task_id=f"branch_{self.task.task_id}",
            python_callable=self._get_task
        )