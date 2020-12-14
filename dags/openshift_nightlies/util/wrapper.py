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
            python_callable=get_task,
            op_args=[self.condition, self.task, self.dummy_task]
        )

        self.branch_task >> self.task 
        self.branch_task >> self.dummy_task 

        

    def get_branch_task(self):
        return self.branch_task
    
    def get_leaf_tasks(self):
        return (self.task, self.dummy_task)



def get_task(condition, task, dummy_task):
    if condition: 
        return task.task_id
    else:
        return dummy_task.task_id