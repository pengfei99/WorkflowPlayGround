# Deploy airflow in production

Deploy airflow in production is different for dev. It will be a long-running daemon process.
In production environment, airflow provides different architectures:
- multi worker nodes: postgres, CeleryExecutor, rabitMQ/redis(message queue)
- single server: postgres, LocalExecutor. (No need for message queue)

In this tutorial, we only show the single server setup.


## 1. Install python and system dependencies

As we mentioned before, airflow is released as a python packages. So we need to prepare a python virtual environment
to install airflow properly. In debian 11, the default python is 3.9, we don't recommend it at all. 

We recommend you to use pyenv to install python

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
/home/pliu/.pyenv/versions/3.11.9/bin/python3 -m venv /opt/airflow/venv

# Set proper ownership for airflow user
sudo chown -R airflow:airflow /opt/airflow/venv
```
## 2. Configure airflow

### 2.1. Use postgresql as db backend

By default, airflow uses sqlite as db backend, we recommend you to use postgresql

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
# 
# before changing airflow.cfg, you should check postgresql connectivity first
psql -U airflow_user -h localhost airflow_db
```

### airflow.cfg 

Below is an example of config which you need to adapt to your environment. This config works for single server with 
`postgres` and `LocalExecutor`.

```ini

[core]
# Airflow home directory
airflow_home = /opt/airflow/airflow-2.9.2

# Executor type
executor = LocalExecutor

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


### start airflow

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