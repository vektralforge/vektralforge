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

Nota sobre versiones de Python: el driver corre en el contenedor de Airflow
(Python 3.12) y los executors en el de Spark (Python 3.8). PySpark rechaza esa
diferencia cuando hay serialización de código Python, así que este job evita
RDDs y UDFs: la lectura del JSON se hace con boto3 en el driver —son archivos
de pocos KB— y el resto son operaciones de DataFrame que se resuelven en la JVM.
"""

import json
import os
import sys
from datetime import UTC, datetime

import boto3
from pyspark.sql import SparkSession

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

# Las credenciales NO se leen para pasarlas a Spark: se comprueba que estén y
# se dejan en el entorno, donde las resuelven el provider de S3A y boto3. Una
# credencial en un `--conf` viaja en la línea de comandos del proceso y aparece
# en la UI del driver; en el entorno, no.
for _var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
    if _var not in os.environ:
        print(f"✗ Falta la variable de entorno '{_var}'")
        sys.exit(1)

RAW_BUCKET = "raw"
RAW_PREFIX = f"indicadores/fecha={fecha}"
BRONZE_BASE = "s3a://bronze"

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
print(f"→ Spark {spark.version} — procesando indicadores para {fecha}")

# Sin claves explícitas: boto3 las toma de AWS_ACCESS_KEY_ID y
# AWS_SECRET_ACCESS_KEY, las mismas que usa el provider de S3A.
_s3 = boto3.client("s3", endpoint_url=MINIO_ENDPOINT)


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _leer_json(bucket, key):
    """Lee un JSON pequeño desde MinIO. No usa Spark a propósito."""
    obj = _s3.get_object(Bucket=bucket, Key=key)
    return json.loads(obj["Body"].read().decode("utf-8"))


def _valor_a_float(valor):
    """Convierte un valor string o numérico a float.

    mindicador.cl entrega los números en formato chileno: '36.345,67'.
    """
    if valor is None:
        return None
    # Los executors corren Python 3.8: la sintaxis int | float no existe ahí.
    if isinstance(valor, (int, float)):  # noqa: UP038
        return float(valor)
    try:
        return float(str(valor).replace(".", "").replace(",", "."))
    except (ValueError, AttributeError):
        return None


def _construir_filas(data, nombre):
    """Transforma la serie de mindicador.cl en filas planas."""
    filas = []
    for item in data.get("serie", []):
        fecha_item = item.get("fecha", "")
        # mindicador entrega ISO con hora: '2026-05-01T00:00:00.000Z'
        if "T" in fecha_item:
            fecha_item = fecha_item[:10]

        filas.append(
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
    return filas


def _escribir_delta(filas, path, nombre):
    """Escribe las filas en Delta Lake. Retorna cuántas se escribieron."""
    df = spark.createDataFrame(filas)
    df.write.format("delta").mode("append").option("mergeSchema", "true").save(path)
    n = len(filas)
    print(f"  ✓ {nombre}: {n} filas → {path}")
    return n


# ─── Procesamiento ────────────────────────────────────────────────────────────

escritos = {}
vacios = []
fallidos = []

for nombre in INDICADORES:
    print(f"\n→ Procesando {nombre.upper()}...")
    key = f"{RAW_PREFIX}/{nombre}_{anio}.json"
    path_delta = f"{BRONZE_BASE}/indicadores_{nombre}"

    try:
        data = _leer_json(RAW_BUCKET, key)
        filas = _construir_filas(data, nombre)

        if not filas:
            print(f"  ⚠ {nombre.upper()}: serie vacía")
            vacios.append(nombre)
            continue

        escritos[nombre] = _escribir_delta(filas, path_delta, nombre.upper())

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
        print(f"    s3a://bronze/indicadores_{nombre}/  ({n} filas)")

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
