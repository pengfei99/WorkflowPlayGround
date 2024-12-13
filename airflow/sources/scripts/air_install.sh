#!/bin/bash

# set up the home folder for airflow application, it will store all the required files of the airflow
# if not define, when you run the server, it will create the files in ~/airflow
air_root_path=~/opt/airflow

# set up python and airflow version
AIRFLOW_VERSION=2.9.2
PYTHON_VERSION="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

# Add AIRFLOW_HOME to your bashrc if not already present
if ! grep -q "AIRFLOW_HOME=$air_root_path" ~/.bashrc; then
  echo "export AIRFLOW_HOME=\"$air_root_path\"" >> ~/.bashrc
  echo "AIRFLOW_HOME added to ~/.bashrc"
else
  echo "AIRFLOW_HOME is already set in ~/.bashrc"
fi

# Export the environment variable for the current session
export AIRFLOW_HOME="$air_root_path"
echo "AIRFLOW_HOME is set to $AIRFLOW_HOME"

# auto determine the constraint url
CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

# For example: https://raw.githubusercontent.com/apache/airflow/constraints-2.9.2/constraints-no-providers-3.8.txt
pip install "apache-airflow==${AIRFLOW_VERSION}" --constraint "${CONSTRAINT_URL}"
