"""
example_transform.py — Job PySpark: bronze → silver con MERGE ACID.

ROL DE SPARK EN EL LAKEHOUSE:
  1. Escritura ACID sobre Delta Lake (MERGE, UPDATE, DELETE, VACUUM).
     Trino NO puede hacer esto — solo lee.
  2. Transformación ELT batch (raw→bronze→silver→gold).
  3. Streaming Kafka→Delta via Spark Structured Streaming.

Este job implementa el Rol 1 + Rol 2: lee bronze y hace un MERGE en silver.
"""

import os

from delta import DeltaTable, configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://localhost:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")
BRONZE_PATH = "s3a://bronze/example/"
SILVER_PATH = "s3a://silver/example/"


def get_spark() -> SparkSession:
    builder = (
        SparkSession.builder.appName("lakeforge-example-transform")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog"
        )
        .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
        .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
        .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    )
    return configure_spark_with_delta_pip(builder).getOrCreate()


def transform(spark: SparkSession) -> None:
    """
    Lee bronze y hace MERGE ACID en silver.
    MERGE es una operación Delta Lake que solo Spark puede ejecutar.
    Trino no tiene esta capacidad sobre Delta Lake.
    """
    df_bronze = (
        spark.read.format("delta")
        .load(BRONZE_PATH)
        .filter(F.col("activo"))
        .withColumn("fecha_proceso", F.current_timestamp())
        .dropDuplicates(["id"])
    )

    # Inicializar tabla silver si no existe
    if not DeltaTable.isDeltaTable(spark, SILVER_PATH):
        df_bronze.write.format("delta").mode("overwrite").save(SILVER_PATH)
        print(f"✓ Silver inicializado con {df_bronze.count()} filas")
        return

    # MERGE ACID: upsert bronze sobre silver (solo Spark puede hacer esto)
    silver = DeltaTable.forPath(spark, SILVER_PATH)
    silver.alias("target").merge(
        df_bronze.alias("source"), "target.id = source.id"
    ).whenMatchedUpdateAll().whenNotMatchedInsertAll().execute()

    print("✓ MERGE ACID completado en silver")


if __name__ == "__main__":
    spark = get_spark()
    transform(spark)
    spark.stop()
