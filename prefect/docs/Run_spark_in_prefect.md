# Run spark in prefect

Why SparkSession Can’t Just Be a Global Variable

Prefect tasks run in isolation; they serialize input/output.

A SparkSession is not serializable, so you can’t pass it between tasks.

Instead, you need to keep the session alive in the same process where tasks run.


Approaches to Solve It:

## 1. Task Runner with Shared State (Best for Local/Single Agent)

Use Prefect’s task runner state or flow context to store the SparkSession:

```python
from prefect import flow, task
from pyspark.sql import SparkSession

def get_spark():
    if not hasattr(get_spark, "session"):
        get_spark.session = (SparkSession.builder
                             .appName("PrefectSparkApp")
                             .master("spark://spark-master:7077")
                             .getOrCreate())
    return get_spark.session

@task
def task_one():
    spark = get_spark()
    df = spark.range(10)
    return df.count()

@task
def task_two():
    spark = get_spark()
    df = spark.range(100)
    return df.count()

@flow
def spark_flow():
    a = task_one()
    b = task_two()
    print(a, b)

if __name__ == "__main__":
    spark_flow()

```


> get_spark() lazily creates a session once, then reuses it for all tasks in the same agent process.
> 
> 
## 2. Use Subflows Instead of Tasks

If tasks must share a Spark session, wrap Spark work inside a subflow:

```python
@flow
def spark_subflow():
    spark = (SparkSession.builder.appName("Shared").getOrCreate())
    # multiple operations here reuse same session
    df1 = spark.range(10).count()
    df2 = spark.range(100).count()
    return df1, df2

@flow
def main_flow():
    results = spark_subflow()
    print(results)
```
