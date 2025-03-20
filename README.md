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
