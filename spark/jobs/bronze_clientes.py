"""
bronze_clientes.py
Job PySpark: lee CSV desde raw/ y escribe Delta Lake en bronze/.

Compatible con:
  - Spark 3.5.3
  - delta-spark 3.2.0 (NO 4.0.0 — esa requiere Spark 4.x)

Uso:
  spark-submit bronze_clientes.py <fecha>
  Ejemplo: spark-submit bronze_clientes.py 2025-01-15
"""

import os
import sys

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

fecha = sys.argv[1] if len(sys.argv) > 1 else "2025-01-01"

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")

RAW_PATH = f"s3a://raw/clientes/fecha={fecha}/clientes.csv"
BRONZE_PATH = "s3a://bronze/clientes"

builder = (
    SparkSession.builder.appName(f"lakeforge-bronze-clientes-{fecha}")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
    .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
)

spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sparkContext.setLogLevel("WARN")

print(f"→ Spark version: {spark.version}")
print(f"→ Leyendo CSV desde: {RAW_PATH}")

df = spark.read.option("header", "true").option("inferSchema", "true").csv(RAW_PATH)

print(f"→ Filas leídas desde raw: {df.count()}")
df.show()

df_bronze = (
    df.withColumn("fecha_carga", F.lit(fecha))
    .withColumn("fecha_proceso", F.current_timestamp())
    .withColumn("activo", F.col("activo").cast("boolean"))
    .withColumn("monto", F.col("monto").cast("long"))
)

print(f"→ Escribiendo Delta Lake en: {BRONZE_PATH}")

(df_bronze.write.format("delta").mode("append").option("mergeSchema", "true").save(BRONZE_PATH))

print(f"✓ {df_bronze.count()} filas escritas en Delta Lake bronze/clientes")
spark.stop()
