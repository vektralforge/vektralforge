"""
kafka_to_delta_stream.py — Spark Structured Streaming: Kafka → Delta Lake.

ROL: Rol 3 de Spark en el lakehouse.
  Lee eventos desde Kafka en micro-batches y los escribe en Delta Lake
  con semántica exactly-once. Trino puede consultar los datos resultantes
  en tiempo real vía la tabla Delta registrada en Hive Metastore.
"""

import os

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType, TimestampType

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "events")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")
BRONZE_PATH = "s3a://bronze/events/"
CHECKPOINT = "s3a://bronze/_checkpoints/events/"

SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("payload", StringType(), True),
        StructField("timestamp", TimestampType(), True),
    ]
)


def get_spark() -> SparkSession:
    builder = (
        SparkSession.builder.appName("lakeforge-kafka-stream")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog"
        )
        .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
        .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
        .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
    )
    return configure_spark_with_delta_pip(builder).getOrCreate()


def stream(spark: SparkSession) -> None:
    """Lee desde Kafka y escribe en Delta Lake con exactly-once."""
    df_kafka = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", KAFKA_BROKERS)
        .option("subscribe", KAFKA_TOPIC)
        .option("startingOffsets", "latest")
        .load()
    )

    df_parsed = (
        df_kafka.select(F.from_json(F.col("value").cast("string"), SCHEMA).alias("data"))
        .select("data.*")
        .withColumn("ingested_at", F.current_timestamp())
    )

    query = (
        df_parsed.writeStream.format("delta")
        .outputMode("append")
        .option("checkpointLocation", CHECKPOINT)
        .start(BRONZE_PATH)
    )
    query.awaitTermination()


if __name__ == "__main__":
    spark = get_spark()
    stream(spark)
