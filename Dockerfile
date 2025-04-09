FROM apache/airflow:latest

# Switch to root user to install dependencies
USER root
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libaio1 \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Install apache-airflow-providers-oracle
RUN pip install --no-cache-dir apache-airflow-providers-oracle
