"""
example_transform.py
Job PySpark de ejemplo: lee desde Delta Lake (bronze), transforma y escribe en silver.
Ejecutar: spark-submit spark/jobs/example_transform.py
"""
import os

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

# ─── configuración ────────────────────────────────────────────────────────────
MINIO_ENDPOINT  = os.getenv("MINIO_ENDPOINT", "http://localhost:9000")
MINIO_ACCESS    = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET    = os.getenv("MINIO_SECRET_KEY", "minioadmin")
BRONZE_PATH     = "s3a://bronze/example/"
SILVER_PATH     = "s3a://silver/example/"


def get_spark() -> SparkSession:
    builder = (
        SparkSession.builder
        .appName("lakeforge-example-transform")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
        .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
        .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    )
    return configure_spark_with_delta_pip(builder).getOrCreate()


def transform(spark: SparkSession) -> None:
    """Lee bronze, aplica transformaciones y escribe en silver."""
    df = spark.read.format("delta").load(BRONZE_PATH)

    df_silver = (
        df
        .filter(F.col("activo") == True)
        .withColumn("fecha_proceso", F.current_timestamp())
        .dropDuplicates(["id"])
    )

    (
        df_silver.write
        .format("delta")
        .mode("overwrite")
        .option("mergeSchema", "true")
        .save(SILVER_PATH)
    )

    print(f"✓ Escritas {df_silver.count()} filas en silver")


if __name__ == "__main__":
    spark = get_spark()
    transform(spark)
    spark.stop()
