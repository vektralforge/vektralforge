"""
bronze_cmf.py
Job PySpark: lee JSON de indicadores CMF desde raw/ y escribe Delta Lake en bronze/.

Tablas generadas:
  - bronze/cmf_uf/       → UF diaria
  - bronze/cmf_ipc/      → IPC mensual
  - bronze/cmf_tmc/      → TMC mensual por tipo
  - bronze/cmf_divisas/  → Dólar, Euro, Yen, Libra Esterlina diario

Uso:
  spark-submit bronze_cmf.py <fecha>
  Ejemplo: spark-submit bronze_cmf.py 2026-05-14
"""

import json
import os
import sys
from datetime import datetime

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DoubleType,
    StringType,
    StructField,
    StructType,
)

# ─── Argumentos ───────────────────────────────────────────────────────────────
fecha = sys.argv[1] if len(sys.argv) > 1 else datetime.now().strftime("%Y-%m-%d")
anio = fecha[:4]
mes = fecha[5:7]

# ─── Config ───────────────────────────────────────────────────────────────────
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")
RAW_PREFIX = f"s3a://raw/cmf/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"

# ─── SparkSession ─────────────────────────────────────────────────────────────
builder = (
    SparkSession.builder.appName(f"lakeforge-bronze-cmf-{fecha}")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS)
    .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET)
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.sql.shuffle.partitions", "2")
)

spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sparkContext.setLogLevel("WARN")
print(f"→ Spark {spark.version} iniciado")
print(f"→ Procesando CMF para fecha: {fecha}")


def _leer_json_s3(path: str) -> dict:
    """Lee un JSON desde S3A y retorna como dict."""
    rdd = spark.sparkContext.textFile(path)
    contenido = "\n".join(rdd.collect())
    return json.loads(contenido)


def _valor_a_float(valor_str: str) -> float:
    """Convierte valor CMF '36.345,67' a float 36345.67"""
    if not valor_str:
        return None
    return float(valor_str.replace(".", "").replace(",", "."))


def _escribir_delta(df, path: str, nombre: str) -> None:
    """Escribe DataFrame en Delta Lake con append."""
    (df.write.format("delta").mode("append").option("mergeSchema", "true").save(path))
    count = df.count()
    print(f"✓ {nombre}: {count} filas escritas en {path}")


# ─── UF ───────────────────────────────────────────────────────────────────────
print("\n→ Procesando UF...")
try:
    data_uf = _leer_json_s3(f"{RAW_PREFIX}/uf.json")
    ufs = data_uf.get("UFs", {}).get("UF", [])
    if isinstance(ufs, dict):
        ufs = [ufs]

    if ufs:
        rows_uf = []
        for u in ufs:
            rows_uf.append(
                {
                    "fecha": u.get("Fecha", ""),
                    "valor": _valor_a_float(u.get("Valor", "0")),
                    "indicador": "UF",
                    "fuente": "CMF Chile",
                    "fecha_proceso": fecha,
                    "anio": int(anio),
                    "mes": int(mes),
                }
            )

        schema_uf = StructType(
            [
                StructField("fecha", StringType(), True),
                StructField("valor", DoubleType(), True),
                StructField("indicador", StringType(), True),
                StructField("fuente", StringType(), True),
                StructField("fecha_proceso", StringType(), True),
                StructField("anio", StringType(), True),
                StructField("mes", StringType(), True),
            ]
        )

        df_uf = spark.createDataFrame(rows_uf)
        df_uf = df_uf.withColumn("anio", F.col("anio").cast("integer"))
        df_uf = df_uf.withColumn("mes", F.col("mes").cast("integer"))
        _escribir_delta(df_uf, f"{BRONZE_BASE}/cmf_uf", "UF")
except Exception as e:
    print(f"⚠ Error procesando UF: {e}")


# ─── IPC ──────────────────────────────────────────────────────────────────────
print("\n→ Procesando IPC...")
try:
    data_ipc = _leer_json_s3(f"{RAW_PREFIX}/ipc.json")
    ipcs = data_ipc.get("IPCs", {}).get("IPC", [])
    if isinstance(ipcs, dict):
        ipcs = [ipcs]

    if ipcs:
        rows_ipc = []
        for i in ipcs:
            rows_ipc.append(
                {
                    "fecha": i.get("Fecha", ""),
                    "valor": _valor_a_float(i.get("Valor", "0")),
                    "indicador": "IPC",
                    "fuente": "CMF Chile",
                    "fecha_proceso": fecha,
                    "anio": int(anio),
                    "mes": int(mes),
                }
            )

        df_ipc = spark.createDataFrame(rows_ipc)
        _escribir_delta(df_ipc, f"{BRONZE_BASE}/cmf_ipc", "IPC")
except Exception as e:
    print(f"⚠ Error procesando IPC: {e}")


# ─── TMC ──────────────────────────────────────────────────────────────────────
print("\n→ Procesando TMC...")
try:
    data_tmc = _leer_json_s3(f"{RAW_PREFIX}/tmc.json")
    tmcs = data_tmc.get("TMCs", {}).get("TMC", [])
    if isinstance(tmcs, dict):
        tmcs = [tmcs]

    if tmcs:
        rows_tmc = []
        for t in tmcs:
            rows_tmc.append(
                {
                    "fecha": t.get("Fecha", ""),
                    "fecha_hasta": t.get("Hasta", ""),
                    "tipo_credito": t.get("TipoCredito", ""),
                    "descripcion": t.get("Descripcion", ""),
                    "valor_tmc": _valor_a_float(t.get("ValorTMC", "0")),
                    "valor_tip": _valor_a_float(t.get("ValorTIP", "0")),
                    "indicador": "TMC",
                    "fuente": "CMF Chile",
                    "fecha_proceso": fecha,
                    "anio": int(anio),
                    "mes": int(mes),
                }
            )

        df_tmc = spark.createDataFrame(rows_tmc)
        _escribir_delta(df_tmc, f"{BRONZE_BASE}/cmf_tmc", "TMC")
except Exception as e:
    print(f"⚠ Error procesando TMC: {e}")


# ─── DIVISAS ──────────────────────────────────────────────────────────────────
print("\n→ Procesando Divisas...")
try:
    data_divisas = _leer_json_s3(f"{RAW_PREFIX}/divisas.json")

    # Mapeo de clave JSON → nombre de divisa
    divisas_map = {
        "dolar": ("Dolares", "Dolar"),
        "euro": ("Euros", "Euro"),
        "yen": ("Yenes", "Yen"),
        "libra_esterlina": ("LibrasEsterlinass", "LibraEsterlina"),
    }

    rows_divisas = []
    for nombre_divisa, (clave_plural, clave_singular) in divisas_map.items():
        if nombre_divisa not in data_divisas:
            continue
        data = data_divisas[nombre_divisa]
        items = data.get(clave_plural, {}).get(clave_singular, [])
        if isinstance(items, dict):
            items = [items]
        if not isinstance(items, list):
            continue

        for item in items:
            rows_divisas.append(
                {
                    "fecha": item.get("Fecha", ""),
                    "valor": _valor_a_float(item.get("Valor", "0")),
                    "divisa": nombre_divisa.upper().replace("_", " "),
                    "indicador": "DIVISA",
                    "fuente": "CMF Chile",
                    "fecha_proceso": fecha,
                    "anio": int(anio),
                    "mes": int(mes),
                }
            )

    if rows_divisas:
        df_divisas = spark.createDataFrame(rows_divisas)
        _escribir_delta(df_divisas, f"{BRONZE_BASE}/cmf_divisas", "Divisas")
    else:
        print("  ⚠ Sin datos de divisas para este período")

except Exception as e:
    print(f"⚠ Error procesando Divisas: {e}")


# ─── Resumen ──────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print(f"✓ Bronze CMF completado para fecha: {fecha}")
print("  Tablas Delta Lake actualizadas:")
print("    s3a://bronze/cmf_uf/")
print("    s3a://bronze/cmf_ipc/")
print("    s3a://bronze/cmf_tmc/")
print("    s3a://bronze/cmf_divisas/")
print("=" * 60)

spark.stop()
