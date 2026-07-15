"""
bronze_arclim.py
Job PySpark: transforma datos ARClim raw → Delta Lake bronze

Tablas generadas:
  s3a://bronze/arclim_indicadores/   ← catálogo de indicadores climáticos
  s3a://bronze/arclim_comunas/       ← riesgo climático por las 346 comunas
  s3a://bronze/arclim_series/        ← series de tiempo 1970-2070

Uso:
  spark-submit bronze_arclim.py <fecha>
  Ejemplo: spark-submit bronze_arclim.py 2026-07-14
"""

import json
import os
import sys
from datetime import datetime

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
)

# ── Argumentos ────────────────────────────────────────────────────────────────
fecha = sys.argv[1] if len(sys.argv) > 1 else datetime.now().strftime("%Y-%m-%d")
anio = fecha[:4]
mes = fecha[5:7]

# ── Config ────────────────────────────────────────────────────────────────────
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")
RAW_PREFIX = f"s3a://raw/arclim/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"

# Indicadores extraídos en el DAG
INDICADORES = [
    "hot_days",
    "consecutive_days_over_25C",
    "dry_days",
    "frost_days",
    "mean_temperature",
    "total_precipitation",
]

# ── SparkSession ──────────────────────────────────────────────────────────────
builder = (
    SparkSession.builder.appName(f"lakeforge-bronze-arclim-{fecha}")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
    .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config(
        "spark.hadoop.fs.s3a.impl",
        "org.apache.hadoop.fs.s3a.S3AFileSystem",
    )
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.sql.shuffle.partitions", "2")
)

spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sparkContext.setLogLevel("WARN")
print(f"→ Spark {spark.version} — procesando ARClim para fecha: {fecha}")


def leer_json_s3(path):
    """Lee un archivo JSON desde S3A."""
    rdd = spark.sparkContext.textFile(path)
    return json.loads("\n".join(rdd.collect()))


def escribir_delta(df, path, nombre, merge_key=None):
    """Escribe DataFrame en Delta Lake."""
    if df.count() == 0:
        print(f"  ⚠ {nombre}: DataFrame vacío, omitiendo")
        return
    df.write.format("delta").mode("append").option("mergeSchema", "true").save(path)
    print(f"  ✓ {nombre}: {df.count()} filas → {path}")


# ── 1. Tabla arclim_indicadores (catálogo) ───────────────────────────────────
print("\n→ Procesando catálogo de indicadores climáticos...")
try:
    data = leer_json_s3(f"{RAW_PREFIX}/indicadores_climaticos.json")
    rows = []
    for item in data.get("data", []):
        rows.append(
            {
                "code": item.get("code", ""),
                "name": item.get("name", ""),
                "description": item.get("description", ""),
                "units": item.get("units", ""),
                "delta_fn": item.get("delta_fn", ""),
                "fecha_carga": fecha,
                "anio": int(anio),
                "mes": int(mes),
            }
        )

    schema = StructType(
        [
            StructField("code", StringType(), True),
            StructField("name", StringType(), True),
            StructField("description", StringType(), True),
            StructField("units", StringType(), True),
            StructField("delta_fn", StringType(), True),
            StructField("fecha_carga", StringType(), True),
            StructField("anio", IntegerType(), True),
            StructField("mes", IntegerType(), True),
        ]
    )

    df_ind = spark.createDataFrame(rows, schema)
    escribir_delta(df_ind, f"{BRONZE_BASE}/arclim_indicadores", "arclim_indicadores")

except Exception as e:
    print(f"  ⚠ Error procesando indicadores: {e}")


# ── 2. Tabla arclim_comunas (riesgo por comuna) ──────────────────────────────
print("\n→ Procesando riesgo climático por comunas...")
try:
    data = leer_json_s3(f"{RAW_PREFIX}/riesgo_comunas.json")

    index = data.get("index", [])
    columns = data.get("columns", [])
    values = data.get("values", [])

    rows = []
    for i, (cod_comuna, row_vals) in enumerate(zip(index, values)):
        row = {
            "cod_comuna": str(cod_comuna),
            "fecha_carga": fecha,
            "anio": int(anio),
            "mes": int(mes),
        }
        for j, col in enumerate(columns):
            val = row_vals[j] if j < len(row_vals) else None
            # Limpiar nombre de columna para Delta Lake (sin $ ni caracteres especiales)
            col_clean = (
                col.replace("$CLIMA$", "clima_")
                .replace("$annual$", "_anual_")
                .replace("$", "_")
                .lower()
            )
            row[col_clean] = val
        rows.append(row)

    if rows:
        df_comunas = spark.createDataFrame(rows)
        escribir_delta(
            df_comunas,
            f"{BRONZE_BASE}/arclim_comunas",
            "arclim_comunas",
        )

except Exception as e:
    print(f"  ⚠ Error procesando comunas: {e}")


# ── 3. Tabla arclim_series (series de tiempo) ─────────────────────────────────
print("\n→ Procesando series de tiempo 1970-2070...")
try:
    data = leer_json_s3(f"{RAW_PREFIX}/series_comunas_capitales.json")

    rows = []
    for cod_comuna, info in data.items():
        nombre = info.get("nombre", "")
        for indicador, serie in info.get("indicadores", {}).items():
            years = serie.get("years", [])
            means = serie.get("mean", [])
            p10s = serie.get("p10", [])
            p90s = serie.get("p90", [])

            for idx_y, year in enumerate(years):
                rows.append(
                    {
                        "cod_comuna": str(cod_comuna),
                        "nombre": nombre,
                        "indicador": indicador,
                        "anio_serie": int(year),
                        "valor_medio": float(means[idx_y]) if idx_y < len(means) else None,
                        "valor_p10": float(p10s[idx_y]) if idx_y < len(p10s) else None,
                        "valor_p90": float(p90s[idx_y]) if idx_y < len(p90s) else None,
                        "escenario": "ssp585",
                        "fecha_carga": fecha,
                        "anio": int(anio),
                        "mes": int(mes),
                    }
                )

    if rows:
        df_series = spark.createDataFrame(rows)
        escribir_delta(
            df_series,
            f"{BRONZE_BASE}/arclim_series",
            "arclim_series",
        )

except Exception as e:
    print(f"  ⚠ Error procesando series: {e}")


# ── Resumen ───────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print(f"✓ Bronze ARClim completado para fecha: {fecha}")
print("  Tablas Delta Lake actualizadas:")
print("    s3a://bronze/arclim_indicadores/")
print("    s3a://bronze/arclim_comunas/")
print("    s3a://bronze/arclim_series/")
print("=" * 60)

spark.stop()
