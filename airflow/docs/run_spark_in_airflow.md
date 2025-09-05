# Run spark in airflow

We have two ways to run spark in airflow:
- use bash operator to call spark-submit
- use pyspark code directly in dag

## 0. Install spark and hadoop in your server

You can find the doc [here](https://github.com/pengfei99/PySparkCommonFunc/tree/main/docs)

## 1. Use spark submit


```python
# in word_count_dag.py
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

default_args = {
    "owner": "pliu",
    "depends_on_past": False,
    "retries": 0,
}

with DAG(
    dag_id="spark_submit_example",
    default_args=default_args,
    start_date=datetime(2025, 9, 3),
    schedule_interval=None,
    catchup=False,
) as dag:

    spark_submit_task = BashOperator(
        task_id="spark_submit_job",
        bash_command="""
/opt/spark/spark-4.0.0/bin/spark-submit \
  --master local[*] \
  --deploy-mode client \
  --name airflow_spark_job \
  /opt/demo/jobs/wordcount.py
""",
        env={
            "JAVA_HOME": "/opt/java/jdk-21.0.2",
            "SPARK_HOME": "/opt/spark/spark-4.0.0",
            "HADOOP_HOME": "/opt/hadoop/hadoop-3.3.6"
        }
    )
```

```python
# /opt/jobs/wordcount.py
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("WordCount").getOrCreate()

data = spark.read.text("/opt/demo/data/input.txt")
words = data.selectExpr("explode(split(value, ' ')) as word")
word_counts = words.groupBy("word").count()

word_counts.write.mode("overwrite").csv("/opt/demo/data/output_wordcount")

spark.stop()
```


## 2. Use pyspark in the dag config file

When you run pyspark in airflow, depends on your spark version, you may encounter the below error 
`java.io.IOException: Failed to create a temp directory (under artifacts) after 10 attempts!`.

**Spark 4.0** now uses two key directories:
- **spark.local.dir**: where shuffle/temp data goes
- **spark.sql.artifact.dir**: new in Spark 4.0, used for plan artifacts

> I can't solve this problem at all

```python
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
from pyspark.sql import SparkSession

def wordcount():
    # Add env vars for Spark before creating SparkSession
    os.environ["JAVA_HOME"] = "/opt/java/jdk-21.0.2"
    os.environ["SPARK_HOME"] = "/opt/spark/spark-4.0.0"
    os.environ["HADOOP_HOME"] = "/opt/hadoop/hadoop-3.3.6"
    os.environ["PYSPARK_PYTHON"] = "/home/pliu/.pyenv/versions/airflow-env/bin/python"
    local_tmp = "/opt/airflow/tmp"
    artifact_dir = "/opt/airflow/artifacts"
    
    spark = (
        SparkSession.builder
        .master("local[*]")
        .appName("WordCount")
        .config("spark.local.dir", local_tmp)
        .config("spark.sql.artifact.dir", artifact_dir)
        .getOrCreate()
    )
    data = spark.read.text("/opt/demo/data/input.txt")
    words = data.selectExpr("explode(split(value, ' ')) as word")
    word_counts = words.groupBy("word").count()
    word_counts.show()
    word_counts.write.mode("overwrite").csv("/opt/demo/data/output_wordcount")
    spark.stop()

with DAG(
    "pyspark_direct_example",
    start_date=datetime(2025, 9, 3),
    schedule_interval=None,
    catchup=False,
) as dag:
    run_job = PythonOperator(task_id="wordcount_task", python_callable=wordcount)
```

```python
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import logging

def wordcount():
    """
    PySpark word count function with proper error handling and logging
    """
    # Set up logging
    logger = logging.getLogger(__name__)
    
    try:
        # Import PySpark inside the function to avoid import issues in Airflow
        from pyspark.sql import SparkSession
        
        # Set environment variables before creating SparkSession
        os.environ["JAVA_HOME"] = "/opt/java/jdk-21.0.2"
        os.environ["SPARK_HOME"] = "/opt/spark/spark-4.0.0"
        os.environ["HADOOP_HOME"] = "/opt/hadoop/hadoop-3.3.6"
        os.environ["PYSPARK_PYTHON"] = "/home/pliu/.pyenv/versions/airflow-env/bin/python"
        
        # Define paths
        local_tmp = "/opt/airflow/tmp"
        artifact_dir = "/opt/airflow/artifacts"
        input_path = "/opt/demo/data/input.txt"
        output_path = "/opt/demo/data/output_wordcount"
        
        # Ensure directories exist
        os.makedirs(local_tmp, exist_ok=True)
        os.makedirs(artifact_dir, exist_ok=True)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Check if input file exists
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")
        
        logger.info("Creating Spark session...")
        
        # Create Spark session with proper configuration
        spark = (
            SparkSession.builder
            .master("local[*]")
            .appName("WordCount_Airflow")
            .config("spark.local.dir", local_tmp)
            .config("spark.sql.artifact.dir", artifact_dir)
            .config("spark.sql.adaptive.enabled", "true")
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
            .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
            .config("spark.sql.execution.arrow.pyspark.enabled", "true")
            # Add memory configurations for better performance
            .config("spark.driver.memory", "2g")
            .config("spark.executor.memory", "2g")
            .config("spark.driver.maxResultSize", "1g")
            .getOrCreate()
        )
        
        # Set log level to reduce verbose output
        spark.sparkContext.setLogLevel("WARN")
        
        logger.info("Reading input data...")
        
        # Read the text file
        data = spark.read.text(input_path)
        
        # Perform word count operations
        logger.info("Processing word count...")
        
        # Split lines into words and explode
        words = data.selectExpr("explode(split(lower(trim(value)), '\\\\s+')) as word")
        
        # Filter out empty strings and count words
        word_counts = (words
                      .filter("word != ''")
                      .filter("word != ' '")
                      .groupBy("word")
                      .count()
                      .orderBy("count", ascending=False))
        
        # Show results (limit output for large datasets)
        logger.info("Top 20 most frequent words:")
        word_counts.show(20, truncate=False)
        
        # Write results to output
        logger.info(f"Writing results to {output_path}")
        (word_counts
         .coalesce(1)  # Single output file
         .write
         .mode("overwrite")
         .option("header", "true")
         .csv(output_path))
        
        # Get total word count for logging
        total_words = words.count()
        unique_words = word_counts.count()
        
        logger.info(f"Processing completed successfully!")
        logger.info(f"Total words: {total_words}")
        logger.info(f"Unique words: {unique_words}")
        
        return {
            "status": "success",
            "total_words": total_words,
            "unique_words": unique_words,
            "output_path": output_path
        }
        
    except Exception as e:
        logger.error(f"Error in wordcount function: {str(e)}")
        raise
    
    finally:
        # Ensure Spark session is properly closed
        try:
            if 'spark' in locals():
                logger.info("Stopping Spark session...")
                spark.stop()
        except Exception as e:
            logger.warning(f"Error stopping Spark session: {str(e)}")

# DAG definition
default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
}

with DAG(
    "pyspark_wordcount_dag",
    default_args=default_args,
    description='A PySpark word count DAG',
    schedule_interval=None,  # Manual trigger
    start_date=datetime(2025, 9, 3),
    catchup=False,
    tags=['pyspark', 'wordcount', 'etl'],
    max_active_runs=1,  # Prevent concurrent runs
) as dag:
    
    wordcount_task = PythonOperator(
        task_id="wordcount_task",
        python_callable=wordcount,
        provide_context=True,  # Provides context to the function if needed
    )
```
