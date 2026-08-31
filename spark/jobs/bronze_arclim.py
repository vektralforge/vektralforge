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

Código de salida:
  0 — al menos una tabla escrita
  1 — ninguna tabla escrita, o falta configuración

Los JSON se leen con boto3 en el driver en lugar de sparkContext.textFile():
son archivos de pocos MB que de todas formas acaban íntegros en memoria del
driver, y evitar RDDs de Python elimina una fuente de fallos cuando driver y
executors no comparten exactamente la misma versión del intérprete.
"""

import json
import os
import sys
from datetime import UTC, datetime

import boto3
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
)

# ── Argumentos ────────────────────────────────────────────────────────────────
fecha = sys.argv[1] if len(sys.argv) > 1 else datetime.now(UTC).strftime("%Y-%m-%d")
anio = fecha[:4]
mes = fecha[5:7]

# ── Config ────────────────────────────────────────────────────────────────────
# Sin valores por defecto: una credencial silenciosamente incorrecta produce un
# error de S3 confuso mucho después. Es preferible fallar aquí.
try:
    MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
except KeyError as e:
    print(f"✗ Falta la variable de entorno {e}")
    sys.exit(1)

# Las credenciales NO se leen para pasarlas a Spark: se comprueba que estén y
# se dejan en el entorno, donde las resuelven el provider de S3A y boto3. Una
# credencial en un `--conf` viaja en la línea de comandos del proceso y aparece
# en la UI del driver; en el entorno, no.
for _var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
    if _var not in os.environ:
        print(f"✗ Falta la variable de entorno '{_var}'")
        sys.exit(1)

RAW_BUCKET = "raw"
RAW_PREFIX = f"arclim/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"

# ── SparkSession ──────────────────────────────────────────────────────────────
# Sin configure_spark_with_delta_pip: los JAR de Delta están tanto en
# /opt/spark/jars del cluster como en el pyspark del contenedor de Airflow.
spark = (
    SparkSession.builder.appName(f"vektralforge-bronze-arclim-{fecha}")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    .config(
        "spark.hadoop.fs.s3a.aws.credentials.provider",
        "software.amazon.awssdk.auth.credentials.EnvironmentVariableCredentialsProvider",
    )
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.sql.shuffle.partitions", "2")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")
print(f"→ Spark {spark.version} — procesando ARClim para fecha: {fecha}")

# Sin claves explícitas: boto3 las toma de AWS_ACCESS_KEY_ID y
# AWS_SECRET_ACCESS_KEY, las mismas que usa el provider de S3A.
_s3 = boto3.client("s3", endpoint_url=MINIO_ENDPOINT)

escritos = {}
vacios = []
fallidos = []


# ── Helpers ───────────────────────────────────────────────────────────────────


def leer_json(key):
    """Lee un JSON desde MinIO. No usa Spark a propósito."""
    obj = _s3.get_object(Bucket=RAW_BUCKET, Key=f"{RAW_PREFIX}/{key}")
    return json.loads(obj["Body"].read().decode("utf-8"))


def escribir_delta(df, path, nombre):
    """Escribe el DataFrame en Delta Lake y devuelve el número de filas.

    Devuelve 0 sin escribir si el DataFrame está vacío, para que quien llama
    pueda distinguir 'sin datos' de 'escrito'.
    """
    n = df.count()
    if n == 0:
        print(f"  ⚠ {nombre}: DataFrame vacío, omitiendo")
        return 0
    df.write.format("delta").mode("append").option("mergeSchema", "true").save(path)
    print(f"  ✓ {nombre}: {n} filas → {path}")
    return n


def registrar(nombre, n):
    if n:
        escritos[nombre] = n
    else:
        vacios.append(nombre)


# ── 1. arclim_indicadores (catálogo) ─────────────────────────────────────────
print("\n→ Procesando catálogo de indicadores climáticos...")
try:
    data = leer_json("indicadores_climaticos.json")
    rows = [
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
        for item in data.get("data", [])
    ]

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
    registrar(
        "arclim_indicadores",
        escribir_delta(df_ind, f"{BRONZE_BASE}/arclim_indicadores", "arclim_indicadores"),
    )

except Exception as e:
    print(f"  ✗ arclim_indicadores: {type(e).__name__}: {e}")
    fallidos.append(("arclim_indicadores", f"{type(e).__name__}: {e}"))


# ── 2. arclim_comunas (riesgo por comuna) ────────────────────────────────────
print("\n→ Procesando riesgo climático por comunas...")
try:
    payload = leer_json("riesgo_comunas.json")
    # La API de ARClim anida la respuesta bajo "data"; el resto de endpoints no.
    contenido = payload.get("data", payload)

    index = contenido.get("index", [])
    columns = contenido.get("columns", [])
    values = contenido.get("values", [])

    rows = []
    for cod_comuna, row_vals in zip(index, values):
        row = {
            "cod_comuna": str(cod_comuna),
            "fecha_carga": fecha,
            "anio": int(anio),
            "mes": int(mes),
        }
        for j, col in enumerate(columns):
            # Delta Lake no admite $ ni otros caracteres especiales en los
            # nombres de columna; ARClim los usa en sus atributos climáticos.
            col_clean = (
                col.replace("$CLIMA$", "clima_")
                .replace("$annual$", "_anual_")
                .replace("$", "_")
                .lower()
            )
            row[col_clean] = row_vals[j] if j < len(row_vals) else None
        rows.append(row)

    if rows:
        registrar(
            "arclim_comunas",
            escribir_delta(
                spark.createDataFrame(rows),
                f"{BRONZE_BASE}/arclim_comunas",
                "arclim_comunas",
            ),
        )
    else:
        print("  ⚠ arclim_comunas: sin filas")
        vacios.append("arclim_comunas")

except Exception as e:
    print(f"  ✗ arclim_comunas: {type(e).__name__}: {e}")
    fallidos.append(("arclim_comunas", f"{type(e).__name__}: {e}"))


# ── 3. arclim_series (series de tiempo) ──────────────────────────────────────
print("\n→ Procesando series de tiempo 1970-2070...")
try:
    data = leer_json("series_comunas_capitales.json")

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
        registrar(
            "arclim_series",
            escribir_delta(
                spark.createDataFrame(rows),
                f"{BRONZE_BASE}/arclim_series",
                "arclim_series",
            ),
        )
    else:
        print("  ⚠ arclim_series: sin filas")
        vacios.append("arclim_series")

except Exception as e:
    print(f"  ✗ arclim_series: {type(e).__name__}: {e}")
    fallidos.append(("arclim_series", f"{type(e).__name__}: {e}"))


# ── Resumen ───────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print(f"Bronze ARClim — fecha {fecha}")
print("=" * 60)

if escritos:
    total = sum(escritos.values())
    print(f"\n✓ Escritas {len(escritos)}/3 tablas ({total} filas)")
    for nombre, n in escritos.items():
        print(f"    s3a://bronze/{nombre}/  ({n} filas)")

if vacios:
    print(f"\n⚠ Sin datos: {', '.join(vacios)}")

if fallidos:
    print(f"\n✗ Con error: {len(fallidos)}")
    for nombre, err in fallidos:
        print(f"    {nombre}: {err}")

print("\n" + "=" * 60)

spark.stop()

# Un job que reporta éxito sin haber escrito nada es peor que uno que falla: los
# dashboards siguen mostrando datos antiguos y nadie se entera.
if not escritos:
    print("✗ Ninguna tabla ARClim llegó a bronze.")
    sys.exit(1)

if fallidos:
    print(f"⚠ Completado con {len(fallidos)} error(es).")
