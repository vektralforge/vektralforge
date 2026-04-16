"""
register_tables.py
Registra las tablas Delta Lake en Hive Metastore para que Trino pueda verlas.
Ejecutar una vez después de crear nuevas tablas con Spark.
"""

import os

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")

builder = (
    SparkSession.builder.appName("lakeforge-register-tables")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
    .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.hadoop.hive.metastore.uris", "thrift://hive-metastore:9083")
    .enableHiveSupport()
)

spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sparkContext.setLogLevel("WARN")

# Crear bases de datos si no existen
spark.sql("CREATE DATABASE IF NOT EXISTS bronze LOCATION 's3a://bronze/'")
spark.sql("CREATE DATABASE IF NOT EXISTS silver LOCATION 's3a://silver/'")
spark.sql("CREATE DATABASE IF NOT EXISTS gold   LOCATION 's3a://gold/'")

# Registrar tabla clientes en bronze
spark.sql("""
    CREATE TABLE IF NOT EXISTS bronze.clientes
    USING delta
    LOCATION 's3a://bronze/clientes'
""")

print("✓ Tablas registradas en Hive Metastore:")
spark.sql("SHOW TABLES IN bronze").show()
spark.sql("SELECT COUNT(*) as total FROM bronze.clientes").show()

spark.stop()
