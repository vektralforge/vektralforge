"""
dag_indicadores_financieros.py
DAG que consume la API mindicador.cl (sin API Key) y carga los
indicadores financieros chilenos en Delta Lake bronze.

Fuente: https://mindicador.cl/ (gratuito, sin autenticación)
Indicadores: UF, IPC, Dólar, Euro, UTM, TPM

Flujo:
  1. extract_indicadores  → llama API mindicador.cl, guarda JSON en raw/
  2. transform_bronze     → Spark lee raw/ y escribe Delta Lake en bronze/
  3. validar_bronze       → verifica que los datos llegaron correctamente

"""

import json
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# ─── Configuración ────────────────────────────────────────────────────────────
MINDICADOR_BASE = "https://mindicador.cl/api"
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET = os.getenv("MINIO_SECRET_KEY", "minioadmin")

# Indicadores diarios (se actualizan cada día hábil)
INDICADORES_DIARIOS = ["uf", "dolar", "euro", "utm", "tpm"]

# Indicadores mensuales (se publican una vez al mes, pueden estar vacíos)
INDICADORES_MENSUALES = ["ipc"]

DEFAULT_ARGS = {
    "owner": "alephserver",
    "depends_on_past": False,
    "retries": 0,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

# ─── Helpers ──────────────────────────────────────────────────────────────────


def _get_mindicador(endpoint: str) -> dict:
    """Llama a mindicador.cl y retorna JSON. Sin API Key requerida."""
    import urllib.request

    url = f"{MINDICADOR_BASE}/{endpoint}"
    req = urllib.request.Request(url, headers={"User-Agent": "lakeforge/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _s3_client():
    import boto3

    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS,
        aws_secret_access_key=MINIO_SECRET,
    )


def _subir_json(s3, key: str, data: dict) -> None:
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    s3.put_object(Bucket="raw", Key=key, Body=body, ContentType="application/json")
    print(f"  ✓ s3://raw/{key} ({len(body)} bytes)")


# ─── Task 1: Extraer indicadores ──────────────────────────────────────────────


def extract_indicadores(**context):
    """
    Descarga todos los indicadores desde mindicador.cl
    y los guarda en MinIO raw/indicadores/fecha={ds}/*.json

    Notas de frecuencia:
      - Diarios:   UF, Dólar, Euro, UTM, TPM → disponibles cada día hábil
      - Mensuales: IPC → se publica ~día 8 de cada mes (puede estar vacío)
    """
    s3 = _s3_client()
    fecha = context["ds"]
    anio = fecha[:4]
    prefix = f"indicadores/fecha={fecha}"
    resumen = {"fecha": fecha, "fuente": "mindicador.cl", "indicadores": {}}

    # ── Snapshot diario ───────────────────────────────────────────────────────
    print("→ Descargando snapshot diario...")
    try:
        snapshot = _get_mindicador("")
        _subir_json(s3, f"{prefix}/snapshot_diario.json", snapshot)
        print("  ✓ Snapshot diario OK")
    except Exception as e:
        print(f"  ⚠ Error en snapshot diario: {e}")

    # ── Indicadores diarios — serie anual ─────────────────────────────────────
    todos = INDICADORES_DIARIOS + INDICADORES_MENSUALES
    for nombre in todos:
        print(f"→ Descargando {nombre.upper()} {anio}...")
        try:
            data = _get_mindicador(f"{nombre}/{anio}")
            serie = data.get("serie", [])
            _subir_json(s3, f"{prefix}/{nombre}_{anio}.json", data)
            resumen["indicadores"][nombre] = {"registros": len(serie)}
            if len(serie) == 0 and nombre in INDICADORES_MENSUALES:
                print(
                    f"  ⚠ {nombre.upper()}: serie vacía (publicación mensual, puede no estar disponible aún)"
                )
            else:
                print(f"  ✓ {nombre.upper()}: {len(serie)} registros")
        except Exception as e:
            print(f"  ⚠ {nombre.upper()}: error — {e}")
            resumen["indicadores"][nombre] = {"registros": 0, "error": str(e)}

    _subir_json(s3, f"{prefix}/resumen.json", resumen)
    print("\n✓ Extracción completa")
    return resumen


# ─── Task 3: Validar datos en bronze ─────────────────────────────────────────


def validar_bronze(**context):
    """
    Verifica archivos Delta en bronze/indicadores_*
    - Indicadores diarios: ERROR si no tienen datos
    - Indicadores mensuales (IPC): WARNING si no tienen datos (publicación mensual)
    """
    s3 = _s3_client()
    errores = []
    warnings = []

    # Validar indicadores diarios — deben tener datos siempre
    for nombre in INDICADORES_DIARIOS:
        response = s3.list_objects_v2(Bucket="bronze", Prefix=f"indicadores_{nombre}/")
        parquet = [o for o in response.get("Contents", []) if o["Key"].endswith(".parquet")]
        if not parquet:
            errores.append(f"✗ Sin Parquet en bronze/indicadores_{nombre}/")
        else:
            total_mb = sum(o["Size"] for o in parquet) / 1024 / 1024
            print(f"✓ bronze/indicadores_{nombre}/: {len(parquet)} archivos ({total_mb:.2f} MB)")

    # Validar indicadores mensuales — solo WARNING si no tienen datos
    for nombre in INDICADORES_MENSUALES:
        response = s3.list_objects_v2(Bucket="bronze", Prefix=f"indicadores_{nombre}/")
        parquet = [o for o in response.get("Contents", []) if o["Key"].endswith(".parquet")]
        if not parquet:
            warnings.append(
                f"⚠ Sin Parquet en bronze/indicadores_{nombre}/ "
                f"(publicación mensual — puede no estar disponible aún)"
            )
        else:
            total_mb = sum(o["Size"] for o in parquet) / 1024 / 1024
            print(f"✓ bronze/indicadores_{nombre}/: {len(parquet)} archivos ({total_mb:.2f} MB)")

    # Mostrar warnings (no fallan el DAG)
    for w in warnings:
        print(w)

    # Solo fallar si hay errores en indicadores diarios
    if errores:
        for e in errores:
            print(e)
        raise ValueError(f"Validación fallida: {len(errores)} indicadores diarios sin datos")

    print("\n✓ Validación completada")
    if warnings:
        print(f"  {len(warnings)} advertencia(s) en indicadores mensuales (no crítico)")


# ─── DAG ──────────────────────────────────────────────────────────────────────

with DAG(
    dag_id="indicadores_financieros_chile",
    description=(
        "Extrae UF, IPC, Dólar, Euro, UTM y TPM desde mindicador.cl "
        "y los carga en Delta Lake bronze via Spark. Sin API Key requerida."
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 1, 1),
    schedule="0 10 * * MON-FRI",
    catchup=False,
    tags=["indicadores", "uf", "ipc", "dolar", "euro", "mindicador", "bronze"],
) as dag:
    t1 = PythonOperator(
        task_id="extract_indicadores",
        python_callable=extract_indicadores,
    )

    t2 = BashOperator(
        task_id="transform_bronze",
        bash_command=(
            "docker exec docker-compose-spark-master-1 "
            "/opt/spark/bin/spark-submit "
            "--master spark://spark-master:7077 "
            "--driver-memory 512m "
            "--executor-memory 512m "
            "--packages io.delta:delta-spark_2.12:3.2.0 "
            "--conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension "
            "--conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog "
            "--conf spark.hadoop.fs.s3a.endpoint=http://minio:9000 "
            "--conf spark.hadoop.fs.s3a.access.key=minioadmin "
            "--conf spark.hadoop.fs.s3a.secret.key=minioadmin "
            "--conf spark.hadoop.fs.s3a.path.style.access=true "
            "--conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem "
            "--conf spark.hadoop.fs.s3a.connection.ssl.enabled=false "
            "--conf spark.driver.maxResultSize=128m "
            "--conf spark.sql.shuffle.partitions=2 "
            "/opt/spark/jobs/bronze_indicadores.py {{ ds }}"
        ),
        execution_timeout=timedelta(minutes=15),
    )

    t3 = PythonOperator(
        task_id="validar_bronze",
        python_callable=validar_bronze,
    )

    t1 >> t2 >> t3
