"""
bronze_indicadores.py
Job PySpark: lee JSON de indicadores financieros desde raw/ y escribe Delta Lake.

Fuente: mindicador.cl (sin API Key)
Tablas generadas en bronze/:
  - indicadores_uf/
  - indicadores_ipc/
  - indicadores_dolar/
  - indicadores_euro/
  - indicadores_utm/
  - indicadores_tpm/

Uso:
  spark-submit bronze_indicadores.py <fecha>
  Ejemplo: spark-submit bronze_indicadores.py 2026-05-14
"""

import json
import os
import sys
from datetime import datetime

from delta import configure_spark_with_delta_pip
from pyspark.sql import SparkSession

# ─── Argumentos ───────────────────────────────────────────────────────────────
fecha = sys.argv[1] if len(sys.argv) > 1 else datetime.now().strftime("%Y-%m-%d")
anio = fecha[:4]
mes = fecha[5:7]

# ─── Config ───────────────────────────────────────────────────────────────────
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")
RAW_PREFIX = f"s3a://raw/indicadores/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"

INDICADORES = ["uf", "ipc", "dolar", "euro", "utm", "tpm"]

# ─── SparkSession ─────────────────────────────────────────────────────────────
builder = (
    SparkSession.builder.appName(f"lakeforge-bronze-indicadores-{fecha}")
    .config(
        "spark.sql.extensions",
        "io.delta.sql.DeltaSparkSessionExtension",
    )
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
print(f"→ Spark {spark.version} — procesando indicadores para {fecha}")


def _leer_json_s3(path):
    """Lee JSON desde S3A."""
    rdd = spark.sparkContext.textFile(path)
    return json.loads("\n".join(rdd.collect()))


def _valor_a_float(valor):
    """Convierte valor string o número a float."""
    if valor is None:
        return None
    # noqa: UP038 — Spark corre Python 3.8, no soporta int | float
    if isinstance(valor, (int, float)):  # noqa: UP038
        return float(valor)
    try:
        return float(str(valor).replace(".", "").replace(",", "."))
    except (ValueError, AttributeError):
        return None


def _escribir_delta(rows, path, nombre):
    """Escribe lista de dicts en Delta Lake."""
    if not rows:
        print(f"  ⚠ {nombre}: sin datos para escribir")
        return
    df = spark.createDataFrame(rows)
    df.write.format("delta").mode("append").option("mergeSchema", "true").save(path)
    print(f"  ✓ {nombre}: {df.count()} filas → {path}")


# ─── Procesar cada indicador ──────────────────────────────────────────────────
for nombre in INDICADORES:
    print(f"\n→ Procesando {nombre.upper()}...")
    path_json = f"{RAW_PREFIX}/{nombre}_{anio}.json"
    path_delta = f"{BRONZE_BASE}/indicadores_{nombre}"

    try:
        data = _leer_json_s3(path_json)
        serie = data.get("serie", [])

        if not serie:
            print(f"  ⚠ {nombre.upper()}: serie vacía")
            continue

        rows = []
        for item in serie:
            fecha_item = item.get("fecha", "")
            # mindicador retorna fecha ISO: "2026-05-01T00:00:00.000Z"
            if "T" in fecha_item:
                fecha_item = fecha_item[:10]

            rows.append(
                {
                    "fecha": fecha_item,
                    "valor": _valor_a_float(item.get("valor")),
                    "indicador": nombre.upper(),
                    "nombre": data.get("nombre", nombre),
                    "unidad_medida": data.get("unidad_medida", ""),
                    "fuente": "mindicador.cl",
                    "fecha_proceso": fecha,
                    "anio": int(anio),
                    "mes": int(mes),
                }
            )

        _escribir_delta(rows, path_delta, nombre.upper())

    except Exception as e:
        print(f"  ⚠ Error procesando {nombre.upper()}: {e}")

# ─── Resumen ──────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print(f"✓ Bronze indicadores completado para fecha: {fecha}")
print("  Tablas Delta Lake actualizadas:")
for nombre in INDICADORES:
    print(f"    s3a://bronze/indicadores_{nombre}/")
print("=" * 60)

spark.stop()
