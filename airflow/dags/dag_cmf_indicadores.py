"""
dag_cmf_indicadores.py
DAG que consume la API CMF Chile y carga los indicadores financieros en Delta Lake.

Indicadores:
  - UF  (Unidad de Fomento)          → diario
  - IPC (Índice de Precios Consumidor) → mensual
  - TMC (Tasa Interés Máxima Conv.)   → mensual
  - Dólar / Euro / otras divisas      → diario

Flujo:
  1. extract_cmf   → llama API CMF y guarda JSON en MinIO raw/cmf/
  2. transform_bronze → Spark lee raw/ y escribe Delta Lake en bronze/cmf/
  3. validate      → verifica que los datos llegaron correctamente

API CMF: https://api.cmfchile.cl/api-sbifv3/recursos_api/
API Key: registrar en https://api.cmfchile.cl/
"""

import json
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# ─── Configuración ────────────────────────────────────────────────────────────
CMF_API_BASE = "https://api.cmfchile.cl/api-sbifv3/recursos_api"
# API Key de ejemplo CMF (reemplazar con clave real en producción)
# Registrar en: https://api.cmfchile.cl/login/
CMF_API_KEY = os.getenv("CMF_API_KEY", "REMOVED_ROTATED_CREDENTIAL")

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "http://minio:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin")

DEFAULT_ARGS = {
    "owner": "alephserver",
    "depends_on_past": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

# ─── Funciones de extracción ──────────────────────────────────────────────────


def _get_cmf(endpoint: str) -> dict:
    """Llama a la API CMF y retorna JSON."""
    import urllib.request

    url = f"{CMF_API_BASE}/{endpoint}?apikey={CMF_API_KEY}&formato=json"
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _s3_client():
    """Retorna cliente boto3 para MinIO."""
    import boto3

    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )


def _subir_json(s3, bucket: str, key: str, data: dict) -> None:
    """Sube un dict como JSON a MinIO."""
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
    print(f"✓ Subido → s3://{bucket}/{key} ({len(body)} bytes)")


# ─── Task 1: Extraer todos los indicadores ────────────────────────────────────


def extract_cmf(**context):
    """
    Extrae UF, IPC, TMC y divisas desde la API CMF
    y los guarda en MinIO raw/cmf/{fecha}/*.json
    """
    s3 = _s3_client()
    fecha = context["ds"]  # YYYY-MM-DD
    anio = fecha[:4]  # YYYY
    mes = fecha[5:7]  # MM
    prefix = f"cmf/fecha={fecha}"

    resumen = {}

    # ── UF del mes actual ─────────────────────────────────────────────────────
    print("→ Extrayendo UF...")
    data_uf = _get_cmf(f"uf/{anio}/{mes}")
    _subir_json(s3, "raw", f"{prefix}/uf.json", data_uf)
    ufs = data_uf.get("UFs", {}).get("UF", [])
    if isinstance(ufs, dict):
        ufs = [ufs]
    resumen["uf_registros"] = len(ufs)
    print(f"  UF: {len(ufs)} registros")

    # ── IPC del año actual ────────────────────────────────────────────────────
    print("→ Extrayendo IPC...")
    data_ipc = _get_cmf(f"ipc/{anio}")
    _subir_json(s3, "raw", f"{prefix}/ipc.json", data_ipc)
    ipcs = data_ipc.get("IPCs", {}).get("IPC", [])
    if isinstance(ipcs, dict):
        ipcs = [ipcs]
    resumen["ipc_registros"] = len(ipcs)
    print(f"  IPC: {len(ipcs)} registros")

    # ── TMC del año actual ────────────────────────────────────────────────────
    print("→ Extrayendo TMC...")
    data_tmc = _get_cmf(f"tmc/{anio}")
    _subir_json(s3, "raw", f"{prefix}/tmc.json", data_tmc)
    tmcs = data_tmc.get("TMCs", {}).get("TMC", [])
    if isinstance(tmcs, dict):
        tmcs = [tmcs]
    resumen["tmc_registros"] = len(tmcs)
    print(f"  TMC: {len(tmcs)} registros")

    # ── Divisas (Dólar, Euro, Yen, Libra Esterlina) ───────────────────────────
    divisas = {
        "dolar": "dolar",
        "euro": "euro",
        "yen": "yen",
        "libra_esterlina": "libra_esterlina",
    }
    todas_divisas = {}
    for nombre, endpoint in divisas.items():
        print(f"→ Extrayendo {nombre}...")
        try:
            data_divisa = _get_cmf(f"{endpoint}/{anio}/{mes}")
            todas_divisas[nombre] = data_divisa
            # Obtener clave dinámica del primer nivel del JSON
            clave = list(data_divisa.keys())[0] if data_divisa else nombre
            registros = data_divisa.get(clave, {})
            # Intentar obtener lista de registros
            items = list(registros.values())[0] if registros else []
            if isinstance(items, dict):
                items = [items]
            resumen[f"{nombre}_registros"] = len(items) if isinstance(items, list) else 1
            print(f"  {nombre}: OK")
        except Exception as e:
            print(f"  ⚠ {nombre}: error — {e}")
            resumen[f"{nombre}_registros"] = 0

    _subir_json(s3, "raw", f"{prefix}/divisas.json", todas_divisas)

    # ── Subir resumen ─────────────────────────────────────────────────────────
    resumen["fecha_extraccion"] = fecha
    resumen["fuente"] = "API CMF Chile v3"
    _subir_json(s3, "raw", f"{prefix}/resumen.json", resumen)

    print("\n✓ Extracción completa:")
    for k, v in resumen.items():
        print(f"  {k}: {v}")

    return resumen


# ─── Task 3: Validar datos en bronze ─────────────────────────────────────────


def validar_bronze(**context):
    """Verifica que los archivos Delta existen en bronze/cmf/"""
    s3 = _s3_client()
    fecha = context["ds"]

    indicadores = ["uf", "ipc", "tmc", "divisas"]
    errores = []

    for indicador in indicadores:
        response = s3.list_objects_v2(
            Bucket="bronze",
            Prefix=f"cmf_{indicador}/",
        )
        objetos = response.get("Contents", [])
        parquet = [o for o in objetos if o["Key"].endswith(".parquet")]

        if not parquet:
            errores.append(f"✗ Sin archivos Parquet en bronze/cmf_{indicador}/")
        else:
            print(f"✓ bronze/cmf_{indicador}/: {len(parquet)} archivos Parquet")

    if errores:
        for e in errores:
            print(e)
        raise ValueError(f"Validación fallida: {len(errores)} indicadores sin datos")

    print(f"\n✓ Todos los indicadores CMF disponibles en Delta Lake para {fecha}")


# ─── DAG ──────────────────────────────────────────────────────────────────────

with DAG(
    dag_id="cmf_indicadores_financieros",
    description=(
        "Extrae UF, IPC, TMC y divisas desde API CMF Chile "
        "y los carga en Delta Lake bronze via Spark"
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 1, 1),
    schedule="0 9 * * *",  # Todos los días a las 9:00 AM
    catchup=False,
    tags=["cmf", "indicadores", "uf", "ipc", "tmc", "divisas", "bronze"],
) as dag:
    t1 = PythonOperator(
        task_id="extract_cmf",
        python_callable=extract_cmf,
        doc_md="""
        ### Extract CMF
        Llama a la API CMF Chile y descarga:
        - **UF**: valor diario del mes actual
        - **IPC**: valores mensuales del año
        - **TMC**: tasas del año
        - **Divisas**: Dólar, Euro, Yen, Libra Esterlina del mes

        Guarda los JSON en `s3://raw/cmf/fecha={ds}/`.
        """,
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
            "/opt/spark/jobs/bronze_cmf.py {{ ds }}"
        ),
        execution_timeout=timedelta(minutes=15),
        doc_md="""
        ### Transform Bronze
        Job Spark que lee los JSON desde `raw/cmf/`
        y escribe tablas Delta Lake en `bronze/`:
        - `bronze/cmf_uf/`
        - `bronze/cmf_ipc/`
        - `bronze/cmf_tmc/`
        - `bronze/cmf_divisas/`
        """,
    )

    t3 = PythonOperator(
        task_id="validar_bronze",
        python_callable=validar_bronze,
        doc_md="""
        ### Validar Bronze
        Verifica que existen archivos Parquet en cada
        tabla Delta Lake del bronze de CMF.
        """,
    )

    t1 >> t2 >> t3
