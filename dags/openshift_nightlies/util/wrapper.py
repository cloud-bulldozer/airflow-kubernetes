from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.python_operator import BranchPythonOperator

# This Class wraps a task with a conditional and will skip the task if the conditional is true
class ConditionalTask():
    def __init__(self, dag, condition, task):
        self.dag = dag
        self.condition = condition
        self.task = task 
        self.dummy_task = DummyOperator(dag=dag, task_id=f"skip_{task.task_id}")
        self.branch_task = BranchPythonOperator(
            dag=self.dag,
            task_id=f"branch_{self.task.task_id}",
            python_callable=self._get_task
        )

        self.branch_task >> self.task 
        self.branch_task >> self.dummy_task 

    def _get_task(self):
        if condition: 
            return self.task.task_id
        else:
            return self.dummy_task.task_id

    def get_branch_task(self):
        return branch_task
    
    def get_leaf_tasks(self):
        return (self.task, self.dummy_task)