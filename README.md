## **Step 1: Install Docker & Docker Compose**
Ensure **Docker** and **Docker Compose** are installed. If not, install them using:

```sh
sudo apt update && sudo apt install -y docker.io docker-compose
```

Verify installation:
```sh
docker --version
docker-compose --version
```

---

## **Step 2: Set Up Required Services**
Apache Iceberg requires a **Metastore (Hive)** and a **Query Engine (Trino, Spark)**.  
Here, we will use **Trino + MinIO + PostgreSQL (Hive Metastore)**.

Create a `docker-compose.yml` file:

```yaml
version: '3.8'

services:
  minio:
    image: quay.io/minio/minio
    container_name: minio
    ports:
      - "9000:9000"
      - "9090:9090"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: admin123
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9090"

  postgres:
    image: postgres:14
    container_name: postgres
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: hive
      POSTGRES_PASSWORD: hive
      POSTGRES_DB: metastore
    volumes:
      - postgres_data:/var/lib/postgresql/data

  hive-metastore:
    image: apache/hive:4.0.0-alpha-2
    container_name: hive-metastore
    depends_on:
      - postgres
    ports:
      - "9083:9083"
    environment:
      SERVICE_NAME: metastore
      HIVE_METASTORE_URIS: thrift://hive-metastore:9083
      METASTORE_DB_TYPE: postgres
      METASTORE_DB_HOST: postgres
      METASTORE_DB_NAME: metastore
      METASTORE_DB_USER: hive
      METASTORE_DB_PASSWORD: hive
    command: /opt/hive/bin/hive --service metastore

  trino:
    image: trinodb/trino:latest
    container_name: trino
    depends_on:
      - hive-metastore
      - minio
    ports:
      - "8081:8080"
    volumes:
      - ./trino-config:/etc/trino

volumes:
  minio_data:
  postgres_data:
```

---

## **Step 3: Configure Trino for Iceberg**
Create a directory `trino-config` and add a configuration file for Iceberg.

### **trino-config/catalog/iceberg.properties**
```ini
connector.name=iceberg
catalog.type=hive
hive.metastore.uri=thrift://hive-metastore:9083
iceberg.catalog.type=hive
hive.s3.aws-access-key=admin
hive.s3.aws-secret-key=admin123
hive.s3.endpoint=http://minio:9000
hive.s3.path-style-access=true
```

---

## **Step 4: Start the Docker Containers**
Run the following command to start all services:

```sh
docker-compose up -d
```

---
---

If Trino falls due to a new configuration issue:

```
ERROR	main	io.trino.server.Server	Configuration is invalid
==========

Errors:

1) Invalid configuration property node.environment: must not be null (for class io.airlift.node.NodeConfig.environment)
```

### How to Fix It
Need to provide the `node.environment` property by either:
1. Adding a `node.properties` file to `./trino-config`.
2. Adding the property to your existing `config.properties` file.

Create a `node.properties` file in your `./trino-config` directory with at least the `node.environment` property.

- **`~/CustomDataLake/trino-config/node.properties`**:
  ```
  node.environment=dev
  ```
The updated `./trino-config` directory should now look like this:
```
~/CustomDataLake/trino-config/
├── jvm.config
├── config.properties
├── node.properties
└── catalog/
    └── iceberg.properties
```

#### Steps to Apply the Fix

1. **Restart Trino**:
   ```bash
   sudo docker-compose down
   sudo docker-compose up -d
   ```

2. **Verify Startup**:
   - Check the container status:
     ```bash
     sudo docker ps
     ```
     Ensure the `trino` container is running (status `Up`).
   - Check the logs:
     ```bash
     sudo docker logs trino
     ```
     Look for a successful startup message like:
     ```
     INFO  main  io.trino.server.Server  ======== SERVER STARTED ========
     ```
   - Test the UI:
     Open `http://localhost:8081` in your browser.

- Open Trino in your browser → [http://localhost:8081](http://localhost:8081)
---

## **Step 5: Add Apache Airflow (airflow-scheduler, airflow-webserver, airflow-worker)**
```sh
  airflow-db:
    image: postgres:14
    container_name: airflow-db
    restart: always
    ports:
      - "5433:5432"
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - airflow_db:/var/lib/postgresql/data

  airflow-webserver:
    image: apache/airflow:latest
    container_name: airflow-webserver
    depends_on:
      - airflow-db
    ports:
      - "8080:8080"
    environment:
      - AIRFLOW__CORE__EXECUTOR=CeleryExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0
    volumes:
      - airflow_dags:/opt/airflow/dags
      - airflow_logs:/opt/airflow/logs
      - airflow_plugins:/opt/airflow/plugins
    command: webserver

  airflow-scheduler:
    image: apache/airflow:latest
    container_name: airflow-scheduler
    depends_on:
      - airflow-db
      - airflow-webserver
    environment:
      - AIRFLOW__CORE__EXECUTOR=CeleryExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0
    volumes:
      - airflow_dags:/opt/airflow/dags
      - airflow_logs:/opt/airflow/logs
      - airflow_plugins:/opt/airflow/plugins
    command: scheduler

  airflow-worker:
    image: apache/airflow:latest
    container_name: airflow-worker
    depends_on:
      - airflow-scheduler
    environment:
      - AIRFLOW__CORE__EXECUTOR=CeleryExecutor
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@airflow-db:5432/airflow
      - AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0
    volumes:
      - airflow_dags:/opt/airflow/dags
      - airflow_logs:/opt/airflow/logs
      - airflow_plugins:/opt/airflow/plugins
    command: worker

  redis:
    image: redis:latest
    container_name: airflow-redis
    ports:
      - "6379:6379"
    restart: always

volumes:
  minio_data:
  postgres_data:
  airflow_db:
  airflow_dags:
  airflow_logs:
  airflow_plugins:
```

**Before running Airflow services, need to initialize the database using:**

```sh
docker-compose run --rm airflow-webserver airflow db init
```

**Start All Services Again**
   ```sh
   docker-compose up -d
   ```

**Verify Everything is Running**
   ```sh
   docker ps
   ```

#### **Access Web UIs**
- **MinIO Console** → `http://localhost:9090`  
- **Trino Web UI** → `http://localhost:8081`  
- **Apache Airflow Web UI** → `http://localhost:8080` (default login: `airflow/airflow`)  
- **PostgreSQL (Metastore)** → `postgres://hive:hive@localhost:5432/metastore`  
- **PostgreSQL (Airflow)** → `postgres://airflow:airflow@localhost:5433/airflow`  


By default, **Apache Airflow** creates a user named `admin` with the password `admin`. However, in **Docker-based deployments**, may need to create the user manually.  

#### **Check Default Login Credentials**
Try logging in with:  
- **Username:** `admin`  
- **Password:** `admin`  

#### **Create an Admin User Manually**
If the default credentials don’t work, create an admin user by running:  
```sh
docker-compose run --rm airflow-webserver airflow users create \
    --username admin \
    --password admin123 \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com
```
---
