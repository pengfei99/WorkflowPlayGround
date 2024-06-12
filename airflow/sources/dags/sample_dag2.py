import textwrap
from datetime import datetime, timedelta
from airflow.models.dag import DAG
from airflow.operators.bash import BashOperator
with DAG(
    "pengfei_dag2",
    default_args={
        "depends_on_past": False,
        "email": ["pengfei.liu@casd.eu"],
        "email_on_failure": False,
        "email_on_retry": False,
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    description="A simple tutorial DAG",
    schedule=timedelta(days=1),
    start_date=datetime(2021, 1, 1),
    catchup=False,
    tags=["example"],
) as dag:
    t1 = BashOperator(
        task_id="task_1",
        bash_command="echo 'task 1'",
    )

    t2 = BashOperator(
        task_id="task_2",
        depends_on_past=False,
        bash_command="echo 'task 2'",
        retries=3,
    )
    templated_command = textwrap.dedent(
        """
    {% for i in range(5) %}
        echo "task 3"
    {% endfor %}
    """
    )

    t3 = BashOperator(
        task_id="task_3",
        depends_on_past=False,
        bash_command=templated_command,
    )

    t1 >> t2 >> t3
