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

Código de salida:
  0 — al menos un indicador diario procesado
  1 — ningún indicador diario procesado, o falta configuración

Nota sobre versiones de Python: driver y executors corren 3.12 —el Dockerfile de
Spark lo instala desde deadsnakes para que coincidan—, y PySpark rechaza la
ejecución si difieren en versión menor. Aun así el job evita RDDs y UDFs: la
lectura del JSON se hace con boto3 en el driver —son archivos de pocos KB— y el
resto son operaciones de DataFrame que se resuelven en la JVM.
"""

import json
import os
import sys
import time
from datetime import UTC, datetime

import boto3
from pyspark.sql import SparkSession

from transformaciones import filas_indicadores

# ─── Argumentos ───────────────────────────────────────────────────────────────
fecha = sys.argv[1] if len(sys.argv) > 1 else datetime.now(UTC).strftime("%Y-%m-%d")
anio = fecha[:4]
mes = fecha[5:7]

# ─── Configuración ────────────────────────────────────────────────────────────
# Sin valores por defecto: una credencial silenciosamente incorrecta produce un
# error de S3 confuso mucho después. Es preferible fallar aquí.
try:
    MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
except KeyError as e:
    print(f"✗ Falta la variable de entorno {e}")
    sys.exit(1)

# Las credenciales NO se leen aquí para pasarlas a Spark. Tampoco están ya en
# el entorno: el entrypoint del contenedor las escribe al arrancar en dos
# archivos, uno por consumidor —core-site.xml para S3A, un INI del SDK para
# boto3—, y lo que se comprueba es que ese segundo exista. Una credencial en un
# `--conf` viajaría en la línea de comandos del proceso y aparecería en la UI
# del driver; una en el entorno, en `docker inspect`.
_ARCHIVO_CREDENCIALES = os.environ.get("AWS_SHARED_CREDENTIALS_FILE", "")
if not _ARCHIVO_CREDENCIALES or not os.path.isfile(_ARCHIVO_CREDENCIALES):
    print(
        "✗ No hay credenciales de MinIO para boto3: "
        f"AWS_SHARED_CREDENTIALS_FILE={_ARCHIVO_CREDENCIALES!r}"
    )
    sys.exit(1)

HIVE_METASTORE_URIS = os.environ.get("HIVE_METASTORE_URIS", "thrift://hive-metastore:9083")

RAW_BUCKET = "raw"
RAW_PREFIX = f"indicadores/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"
BRONZE_DB = "bronze"

# Diarios: deben tener datos todos los días hábiles.
INDICADORES_DIARIOS = ["uf", "dolar", "euro", "utm", "tpm"]
# Mensuales: el IPC se publica una vez al mes; una serie vacía no es un error.
INDICADORES_MENSUALES = ["ipc"]
INDICADORES = INDICADORES_DIARIOS + INDICADORES_MENSUALES

# ─── SparkSession ─────────────────────────────────────────────────────────────
# Sin configure_spark_with_delta_pip: los JARs de Delta están tanto en
# /opt/spark/jars del cluster como en el pyspark del contenedor de Airflow.
spark = (
    SparkSession.builder.appName(f"vektralforge-bronze-indicadores-{fecha}")
    # El nombre de la app lleva la fecha para distinguir ejecuciones en la UI de
    # Spark, pero OpenLineage toma de ahí el nombre del job: con la fecha dentro,
    # Marquez crearía un job nuevo cada día y el historial quedaría fragmentado.
    .config("spark.openlineage.appName", "vektralforge_bronze_indicadores")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
    # Aquí se fijaba fs.s3a.aws.credentials.provider a
    # EnvironmentVariableCredentialsProvider. Ya no: el proveedor lo declara
    # core-site.xml, que es también donde están las credenciales. Declararlo en
    # dos sitios significa que el de aquí gana, y ganó: con la clave ya fuera
    # del entorno, S3A seguía buscándola ahí y fallaba con «Unable to load
    # credentials from system settings».
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.sql.shuffle.partitions", "2")
    # El catálogo compartido con Trino: sin esto las tablas quedan como rutas
    # sueltas en MinIO y hay que registrarlas a mano en Trino.
    .config("spark.hadoop.hive.metastore.uris", HIVE_METASTORE_URIS)
    .enableHiveSupport()
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# La base apunta a la raíz del bucket, así que cada tabla se materializa en
# s3a://bronze/<tabla>/ — la misma ruta que antes se escribía a mano.
spark.sql(f"CREATE DATABASE IF NOT EXISTS {BRONZE_DB} LOCATION '{BRONZE_BASE}/'")
print(f"→ Spark {spark.version} — procesando indicadores para {fecha}")

# Sin claves explícitas: boto3 las lee del INI que le indica
# AWS_SHARED_CREDENTIALS_FILE, el segundo eslabón de su cadena por defecto.
_s3 = boto3.client("s3", endpoint_url=MINIO_ENDPOINT)


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _leer_json(bucket, key):
    """Lee un JSON pequeño desde MinIO. No usa Spark a propósito."""
    obj = _s3.get_object(Bucket=bucket, Key=key)
    return json.loads(obj["Body"].read().decode("utf-8"))


def _escribir_delta(filas, tabla, nombre):
    """Escribe las filas en Delta Lake. Retorna cuántas se escribieron.

    saveAsTable y no save(ruta): registra la tabla en el Hive Metastore para
    que Trino la vea sin registrarla a mano. La ruta física no cambia.
    """
    df = spark.createDataFrame(filas)
    # replaceWhere y no append: reejecutar la misma fecha reemplaza esa carga en
    # vez de duplicarla. Delta valida que todas las filas escritas cumplan el
    # predicado, así que un error en fecha_proceso falla en vez de colarse.
    (
        df.write.format("delta")
        .mode("overwrite")
        .option("replaceWhere", f"fecha_proceso = '{fecha}'")
        .option("mergeSchema", "true")
        .saveAsTable(f"{BRONZE_DB}.{tabla}")
    )
    n = len(filas)
    print(f"  ✓ {nombre}: {n} filas → {BRONZE_DB}.{tabla}")
    return n


# ─── Procesamiento ────────────────────────────────────────────────────────────

escritos = {}
vacios = []
fallidos = []

for nombre in INDICADORES:
    print(f"\n→ Procesando {nombre.upper()}...")
    key = f"{RAW_PREFIX}/{nombre}_{anio}.json"
    tabla = f"indicadores_{nombre}"

    try:
        data = _leer_json(RAW_BUCKET, key)
        filas = filas_indicadores(data, nombre, fecha, anio, mes)

        if not filas:
            print(f"  ⚠ {nombre.upper()}: serie vacía")
            vacios.append(nombre)
            continue

        escritos[nombre] = _escribir_delta(filas, tabla, nombre.upper())

    except Exception as e:
        print(f"  ✗ {nombre.upper()}: {type(e).__name__}: {e}")
        fallidos.append((nombre, f"{type(e).__name__}: {e}"))

# ─── Resumen ──────────────────────────────────────────────────────────────────

print("\n" + "=" * 60)
print(f"Bronze indicadores — fecha {fecha}")
print("=" * 60)

if escritos:
    total = sum(escritos.values())
    print(f"\n✓ Escritos: {len(escritos)}/{len(INDICADORES)} ({total} filas)")
    for nombre, n in escritos.items():
        print(f"    {BRONZE_DB}.indicadores_{nombre}  ({n} filas)")

if vacios:
    print(f"\n⚠ Sin datos: {', '.join(v.upper() for v in vacios)}")
    mensuales_vacios = [v for v in vacios if v in INDICADORES_MENSUALES]
    if mensuales_vacios:
        print("    (publicación mensual — puede no estar disponible aún)")

if fallidos:
    print(f"\n✗ Con error: {len(fallidos)}")
    for nombre, err in fallidos:
        print(f"    {nombre.upper()}: {err}")

print("\n" + "=" * 60)

# OpenLineage emite sus eventos de forma asíncrona y no expone ninguna forma de
# forzar el vaciado de la cola: no hay flush, ni drain, ni espera al cerrar.
# Cerrar la sesión justo después de la última escritura pierde los eventos de ese
# último segundo. Medido: en una ejecución quedaron sin registrar los datasets de
# arclim_series, indicadores_utm e indicadores_tpm —las últimas tablas de cada
# job—, mientras que los jobs correspondientes sí aparecían en Marquez. Empeoró
# al pasar a replaceWhere, que emite dos eventos por escritura en vez de uno.
#
# Ajustable con OPENLINEAGE_PAUSA_CIERRE; 0 la desactiva.
_pausa_cierre = float(os.environ.get("OPENLINEAGE_PAUSA_CIERRE", "5"))
if _pausa_cierre > 0:
    print(f"\n→ Esperando {_pausa_cierre:g}s a que OpenLineage vacíe su cola de eventos...")
    time.sleep(_pausa_cierre)

spark.stop()

# Un job que reporta éxito sin haber escrito nada es peor que uno que falla: los
# dashboards siguen mostrando datos antiguos y nadie se entera. La validación
# aguas abajo distingue diarios de mensuales; aquí basta con exigir que algún
# indicador diario haya llegado a bronze.
diarios_ok = [n for n in escritos if n in INDICADORES_DIARIOS]
if not diarios_ok:
    print("✗ Ningún indicador diario llegó a bronze.")
    sys.exit(1)

if fallidos:
    print(f"⚠ Completado con {len(fallidos)} error(es).")
