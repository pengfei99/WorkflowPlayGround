# Deploy airflow in production

Deploy airflow in production is different for dev. It will be a long-running daemon process.
In production environment, airflow provides different architectures:
- multi worker nodes: postgres, CeleryExecutor, rabitMQ/redis(message queue)
- single server: postgres, LocalExecutor. (No need for message queue)

In this tutorial, we only show the single server setup.

We will follow the below steps:

- Install python and Apache Airflow
- Install Postgresql and Configuration
- Configure Apache Airflow
- Testing with simple dag
- Write unit file for Airflow to run as a systemd service

## 1. Install airflow

As we mentioned before, **airflow** is released as a `python packages`. So we need to prepare a `python virtual environment`
to install airflow properly. In debian 11, the default python is 3.9, we don't recommend it at all. 

> We recommend you to use pyenv to install python

### 1.1 Use the debian default package(not recommended)
```shell
# 
sudo apt install -y python3-venv python3-dev build-essential libpq-dev libssl-dev libffi-dev

pip3 install virtualenv

# create a new env
virtualenv airflow_venv

# activate venv
source airflow_venv/bin/activate

deactivate

# remove it
rm -rf airflow_venv
```

### 1.2. Use pyenv

```shell
# install dependencies to run the auto installation script
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git 

# download the script and run it
curl https://pyenv.run | bash

# after the above command, you need to add the env var in the output of the above command in to your .bashrc
# below is an example
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# you need to reload your bashrc or restart your shell
source ~/.bashrc

# show the pyenv version
pyenv versions

# list all available version that can be installed  
pyenv install --list

# install a specific version
pyenv install 3.11.7 

# activate a python version as the current python, there are two mode: global and local
pyenv global 3.11.7
pyenv local 3.11.7

# after changing the python version, you can test it with
python -V
```

#### 1.2.1 Create virtual env 

pyenv offers many possibilities to create venv, as our airflow will be managed by systemd, the venv must be
 easy to control by systemd

```shell
# create venv
/home/pliu/.pyenv/versions/3.11.9/bin/python3 -m venv /opt/airflow/airflow-venv

# Set proper ownership for airflow user
sudo chown -R airflow:airflow /opt/airflow/airflow-venv

# to activate it
source /opt/airflow/airflow-venv/bin/activate
```
## 2. Configure airflow

### 2.1. Use postgresql as db backend

By default, airflow uses sqlite as db backend, we recommend you to use postgresql

The doc for installing postgresql is [here](https://github.com/pengfei99/DataCatalogPlayGround/blob/master/OpenMetadata/Deplyement/bare_metal/01.Install_required_modules.md)

Suppose you have created a database and user for airflow in postgresql
```shell
CREATE DATABASE airflow_db;
CREATE USER airflow_user WITH PASSWORD 'changeMe';
ALTER DATABASE airflow_db OWNER TO airflow_user;
ALTER USER airflow_user SET search_path = public;
commit;
```

You need to tell airflow which db it can connect

```shell
# before changing airflow.cfg, you should check postgresql connectivity first
psql -U airflow_user -h localhost airflow_db

# in airflow.cfg, you need to configure airflow to use postgres
# general form: sql_alchemy_conn = postgresql+psycopg2://login:pwd@url/db_name
sql_alchemy_conn = postgresql+psycopg2://airflow_user:pwd@localhost/airflow_db
```

> If your password contains special characters, you need to encod it with URL encoding
> - @ → %40
> - : → %3A 
> - / → %2F
> You also need to add an extra % before
> For example, if you have a password = P@ss:word/123, you need to write P%%40ss%%3Aword%%2F123 in the airflow.cfg

### 2.2 Web server config

Airflow offers a web GUI, so it requires a port to expose the service.

Depends on your requirements, you need to modify the below config.
```ini
[webserver]
# Webserver configuration
web_server_host = 0.0.0.0
web_server_port = 8080
base_url = http://localhost:8080
```

### Complete example of airflow.cfg 

Below is an example of config which you need to adapt to your environment. This config works for single server with 
`postgres` and `LocalExecutor`.

```ini

[core]
# Airflow home directory
airflow_home = /opt/airflow/airflow-2.9.2

# Executor type
executor = LocalExecutor
# recommended for LocalExecutor
store_serialized_dags = True  
# Metadata database (PostgreSQL)
# general form: sql_alchemy_conn = postgresql+psycopg2://login:pwd@url/db_name
sql_alchemy_conn = postgresql+psycopg2://airflow_user:pwd@localhost/airflow_db
# Folder to store DAG files
dags_folder = /opt/airflow/airflow-2.9.2/dags

# Folder for task logs
base_log_folder = /opt/airflow/airflow-2.9.2/logs

# Load example DAGs? set to False in production
load_examples = False

# How many task instances to run in parallel
parallelism = 32

max_active_runs_per_dag = 16

# Default timezone
default_timezone = utc

---

[scheduler]
# How often the scheduler polls for new DAG runs
scheduler_heartbeat_sec = 5
num_runs = -1
job_heartbeat_sec = 5
min_file_process_interval = 30
max_threads = 4

---

[webserver]
# Webserver configuration
web_server_host = 0.0.0.0
web_server_port = 8080
base_url = http://localhost:8080

---

[logging]
# Logging configuration
logging_level = INFO
base_log_folder = /opt/airflow/airflow-2.9.2/logs
remote_logging = False
log_filename_template = {{ ti.dag_id }}/{{ ti.task_id }}/{{ ts }}/{{ try_number }}.log
log_processor_filename_template = {{ filename }}.log
```


## 3 Start airflow for testing

```shell
# init db
airflow db migrate

# create an admin user, it will prompt to ask your password
airflow users create \
    --username admin \
    --firstname Pengfei \
    --lastname Liu \
    --role Admin \
    --email pengfei.liu@casd.eu
    
# start the web server
airflow webserver --port 8080

# start the 
airflow scheduler
```

After the above command, you should be able to access airflow web GUI.

```shell
curl http://localhost:8080
```

### 3.1 Add a test dag

Below is a minimum dag specification to run in airflow

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

# Function to run
def hello():
    print("Hello Airflow!")

# DAG definition
with DAG(
    dag_id="hello_airflow",
    start_date=datetime(2025, 9, 4),
    schedule_interval=None,  # Manual trigger
    catchup=False,
    tags=["test"],
) as dag:

    hello_task = PythonOperator(
        task_id="say_hello",
        python_callable=hello
    )

```

> we can name it as `hello_airflow.py` and place it in `/opt/airflow/airflow-2.9.2/dags`
> If you can't see the dag in your webserver. You need to check the below points
> - airflow scheduler is running
> - DAG file is valid (no syntax error) and finish with .py
> - start_date is in the past.
> - DAG assigned correctly in global scope
> - .py file permissions allow airflow scheduler to read the DAG
> 

```shell
# test dag valid or not
airflow dags list

# expected output
dag_id        | fileloc                                      | owners  | is_paused
==============+==============================================+=========+==========
hello_airflow | /opt/airflow/airflow-2.9.2/dags/workflow1.py | airflow | None

# run the dag as test run
# general form airflow dags test <dag_id> <start_date>
airflow dags test hello_airflow 2025-09-04
```

## 4. Run airflow as systemd service

### 4.1 Web server unit file
```shell
# create airflow-webserver.service
sudo vim /etc/systemd/system/airflow-webserver.service
```
```ini
[Unit]
Description=Airflow webserver
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=pliu
Group=pliu
Type=simple

# Set environment variables
Environment=AIRFLOW_HOME=/opt/airflow/airflow-2.9.2
# for pyenv virtualenv
# Environment=PATH=/home/pliu/.pyenv/versions/airflow-env/bin:/usr/local/bin:/usr/bin:/bin
# for python native venv
Environment=PATH=/opt/airflow/airflow-env/bin:/usr/local/bin:/usr/bin:/bin
# this line is avoid airflow write in /run/airflow.pid, the python venv may not have rights
# by setting this, airflow will write in its own folder
Environment=TMPDIR=/opt/airflow/tmp

# Start command (use pyenv’s venv directly)
# ExecStart=/home/pliu/.pyenv/versions/airflow-env/bin/airflow webserver
ExecStart=/opt/airflow/airflow-env/bin/airflow webserver
ExecStop=/bin/kill -s TERM $MAINPID

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```


### 4.2 Scheduler unit file

```shell
# create airflow-scheduler.service
sudo vim /etc/systemd/system/airflow-scheduler.service
```

```ini
[Unit]
Description=Airflow scheduler
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=pliu
Group=pliu
Type=simple

# Set environment variables
Environment=AIRFLOW_HOME=/opt/airflow/airflow-2.9.2
Environment=PATH=/home/pliu/.pyenv/versions/airflow-env/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/pliu/.pyenv/versions/airflow-env/bin/airflow scheduler
ExecStop=/bin/kill -s TERM $MAINPID

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target

```

### 4.3 Reload systemd for adding new unit files

```shell
sudo systemctl daemon-reload

sudo systemctl start airflow-webserver
sudo systemctl start airflow-scheduler

# you can check the output of the service with 
sudo journalctl -u airflow-webserver -f
```

