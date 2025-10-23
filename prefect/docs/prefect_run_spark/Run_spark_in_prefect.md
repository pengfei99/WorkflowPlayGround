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

A simple wordcount example

```python
from prefect import flow, task
from pyspark.sql import SparkSession

@task
def run_wordcount(source_file:str, out_file:str):
    spark = (
        SparkSession.builder
        .appName("prefect_wordcount")
        .master("local[4]")  # Limit CPU usage
        .config("spark.local.dir", "C:/Users/PLIU/Documents/git/WorkflowPlayGround/prefect/server_conf/spark_temp/pengfei")
        .getOrCreate()
    )

    df = spark.read.text(source_file)
    counts = df.rdd.flatMap(lambda x: x[0].split()) \
                   .map(lambda w: (w, 1)) \
                   .reduceByKey(lambda a, b: a + b)
    counts.toDF(["word", "count"]).write.mode("overwrite").csv(out_file)
    spark.stop()

@flow(name="spark_wordcount_flow")
def main_flow():
    src_file = "C:/Users/PLIU/Documents/git/WorkflowPlayGround/data/source/word_raw.txt"
    out_file= "C:/Users/PLIU/Documents/git/WorkflowPlayGround/data/out/wc_flow_out"
    run_wordcount(src_file,out_file)

if __name__ == "__main__":
    main_flow()
```

> To avoid access conflict for spark multiple users, we need to set up a specific **spark temp dir** per user.
> For example, we can use `spark.local.dir=C:\spark_tmp\<username>`
>

To run your prefect flow, the most easy way is to use `python script call`.

For example, I put the above prefect flow script in the below directory `prefect/server_conf/flows/pengfei/spark_wc_flow.py`
To run it, we can just simply call it

```shell
python prefect/server_conf/flows/pengfei/spark_wc_flow.py

# expected output
10:37:08.970 | INFO    | prefect - Starting temporary server on http://127.0.0.1:8763
See https://docs.prefect.io/v3/concepts/server#how-to-guides for more information on running a dedicated Prefect server.
10:37:12.617 | INFO    | Flow run 'impetuous-coot' - Beginning flow run 'impetuous-coot' for flow 'spark_wordcount_flow'
Setting default log level to "WARN".
To adjust logging level use sc.setLogLevel(newLevel). For SparkR, use setLogLevel(newLevel).
25/10/20 10:37:15 WARN SparkConf: Note that spark.local.dir will be overridden by the value set by the cluster manager (via SPARK_LOCAL_DIRS in mesos/standalone/kubernetes and LOCAL_DIRS in YARN).
25/10/20 10:37:16 WARN Utils: The configured local directories are not expected to be URIs; however, got suspicious values [C:/Users/PLIU/Documents/git/WorkflowPlayGround/prefect/server_conf/spark_temp/pengfei]. Please check your configured local directories.
C:\Users\PLIU\Documents\Tool\spark\spark-3.5.2\python\lib\pyspark.zip\pyspark\shuffle.py:65: UserWarning: Please install psutil to have better support with spilling
10:37:25.903 | INFO    | Task run 'run_wordcount-12d' - Finished in state Completed()
10:37:25.942 | INFO    | Flow run 'impetuous-coot' - Finished in state Completed()
10:37:25.964 | INFO    | prefect - Stopping temporary server on http://127.0.0.1:8763
SUCCESS: The process with PID 18652 (child process of PID 11804) has been terminated.
SUCCESS: The process with PID 11804 (child process of PID 16624) has been terminated.
SUCCESS: The process with PID 16624 (child process of PID 22564) has been terminated.
```

## 3. Best practices for running spark on prefect

Best Practices:

- Use one SparkSession per flow run (avoid per-task sessions).
- Use local[*] to parallelize across all CPU cores.
- Keep Spark jobs self-contained and avoid passing DataFrames between Prefect tasks.
- Use Prefect for orchestration (dependencies, retries), Spark for computation.
- Test locally on Windows, but design workflows so they can later run on Linux cluster or cloud with minimal code change.