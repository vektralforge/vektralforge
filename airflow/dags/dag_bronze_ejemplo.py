"""
dag_bronze_ejemplo.py
DAG de prueba del stack lakeforge completo.

Flujo:
  1. Genera datos sintéticos y los sube a MinIO raw/ como CSV
  2. Lanza job Spark via BashOperator con memoria limitada
  3. Valida que los archivos Delta existen en bronze/
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

DEFAULT_ARGS = {
    "owner": "alephserver",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "email_on_failure": False,
}


def generar_y_subir_raw(**context):
    import csv
    import io
    import os

    import boto3

    clientes = [
        {"id": 1, "nombre": "Empresa Alpha", "activo": "true", "monto": 150000},
        {"id": 2, "nombre": "Empresa Beta", "activo": "true", "monto": 230000},
        {"id": 3, "nombre": "Empresa Gamma", "activo": "false", "monto": 0},
        {"id": 4, "nombre": "Empresa Delta", "activo": "true", "monto": 87500},
        {"id": 5, "nombre": "Empresa Epsilon", "activo": "true", "monto": 312000},
    ]

    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=["id", "nombre", "activo", "monto"])
    writer.writeheader()
    writer.writerows(clientes)

    s3 = boto3.client(
        "s3",
        endpoint_url=os.getenv("MINIO_ENDPOINT", "http://minio:9000"),
        aws_access_key_id=os.getenv("MINIO_ACCESS_KEY", "minioadmin"),
        aws_secret_access_key=os.getenv("MINIO_SECRET_KEY", "minioadmin"),
    )

    fecha = context["ds"]
    key = f"clientes/fecha={fecha}/clientes.csv"
    s3.put_object(
        Bucket="raw",
        Key=key,
        Body=buffer.getvalue().encode("utf-8"),
        ContentType="text/csv",
    )
    print(f"✓ Subidos {len(clientes)} registros a s3://raw/{key}")
    return key


def validar_bronze(**context):
    import os

    import boto3

    s3 = boto3.client(
        "s3",
        endpoint_url=os.getenv("MINIO_ENDPOINT", "http://minio:9000"),
        aws_access_key_id=os.getenv("MINIO_ACCESS_KEY", "minioadmin"),
        aws_secret_access_key=os.getenv("MINIO_SECRET_KEY", "minioadmin"),
    )

    response = s3.list_objects_v2(Bucket="bronze", Prefix="clientes/")
    objetos = response.get("Contents", [])

    if not objetos:
        raise ValueError("✗ No se encontraron archivos en bronze/clientes/")

    parquet_files = [o for o in objetos if o["Key"].endswith(".parquet")]
    print(f"✓ Validación OK: {len(parquet_files)} archivos Parquet en bronze/clientes/")
    for obj in objetos[:5]:
        print(f"  {obj['Key']} ({obj['Size']} bytes)")


with DAG(
    dag_id="bronze_clientes_ejemplo",
    description="Prueba stack completo: raw CSV → Delta Lake bronze via Spark",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["ejemplo", "bronze", "delta", "spark"],
) as dag:
    t1 = PythonOperator(
        task_id="generar_y_subir_raw",
        python_callable=generar_y_subir_raw,
    )

    # Memoria reducida para PoC local:
    # --driver-memory 512m  → driver JVM
    # --executor-memory 512m → executor JVM
    # --conf spark.driver.maxResultSize=128m → límite de resultados
    # --conf spark.sql.shuffle.partitions=2 → mínimo de particiones (dataset pequeño)
    t2 = BashOperator(
        task_id="transformar_a_bronze",
        bash_command=(
            "docker exec docker-compose-spark-master-1 "
            "/opt/spark/bin/spark-submit "
            "--master spark://spark-master:7077 "
            "--driver-memory 512m "
            "--executor-memory 512m "
            "--packages io.delta:delta-spark_2.12:3.2.0 "
            "--conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension "
            "--conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog "
            "--conf spark.hadoop.fs.s3a.endpoint=http://minio:9000 "
            "--conf spark.hadoop.fs.s3a.access.key=minioadmin "
            "--conf spark.hadoop.fs.s3a.secret.key=minioadmin "
            "--conf spark.hadoop.fs.s3a.path.style.access=true "
            "--conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem "
            "--conf spark.hadoop.fs.s3a.connection.ssl.enabled=false "
            "--conf spark.driver.maxResultSize=128m "
            "--conf spark.sql.shuffle.partitions=2 "
            "/opt/spark/jobs/bronze_clientes.py {{ ds }}"
        ),
        execution_timeout=timedelta(minutes=10),
    )

    t3 = PythonOperator(
        task_id="validar_bronze",
        python_callable=validar_bronze,
    )

    t1 >> t2 >> t3
