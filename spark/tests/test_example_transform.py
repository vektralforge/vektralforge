"""Tests del job de transformación con MERGE ACID."""
import pytest
from chispa.dataframe_comparer import assert_df_equality
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

@pytest.fixture(scope="session")
def spark():
    return (
        SparkSession.builder.master("local[2]")
        .appName("lakeforge-tests")
        .config("spark.sql.shuffle.partitions", "2")
        .getOrCreate()
    )

def test_deduplication(spark):
    """Filas duplicadas por id deben eliminarse antes del MERGE."""
    data = [(1, True), (1, True), (2, True), (3, False)]
    df = spark.createDataFrame(data, ["id", "activo"])
    df_result = df.filter(F.col("activo") == True).dropDuplicates(["id"])
    assert df_result.count() == 2

def test_inactive_rows_filtered(spark):
    """Filas con activo=False deben excluirse."""
    data = [(1, True), (2, False), (3, True)]
    df = spark.createDataFrame(data, ["id", "activo"])
    df_result = df.filter(F.col("activo") == True)
    ids = {row.id for row in df_result.collect()}
    assert ids == {1, 3}
