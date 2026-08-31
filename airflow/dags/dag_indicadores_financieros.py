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
import logging
import os
from datetime import UTC, datetime, timedelta

from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.providers.standard.operators.python import PythonOperator

from http_publico import ErrorAPI, crear_sesion, get_json

# Los `print` de una tarea acaban en el log igual, pero sin nivel: una
# advertencia y una traza informativa llegan indistinguibles y no se pueden
# filtrar ni alertar. Con logging, un ⚠ es WARNING y un ✗ es ERROR.
log = logging.getLogger(__name__)

# ─── Configuración ────────────────────────────────────────────────────────────
MINDICADOR_BASE = "https://mindicador.cl/api"
TIMEOUT = 30  # segundos por request
MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
# Las credenciales se quedan en el entorno: boto3 y el provider de S3A las
# resuelven desde AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY. No se pasan por
# `conf` al SparkSubmitOperator: ahí acabarían en la línea de comandos del
# proceso y en la UI del driver.
for _var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
    if _var not in os.environ:
        raise RuntimeError(f"Falta la variable de entorno {_var!r}")
# Indicadores diarios (se actualizan cada día hábil)
INDICADORES_DIARIOS = ["uf", "dolar", "euro", "utm", "tpm"]

# Indicadores mensuales (se publican una vez al mes, pueden estar vacíos)
INDICADORES_MENSUALES = ["ipc"]

DEFAULT_ARGS = {
    "owner": "vektralforge",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    # Sin timeout, una tarea colgada contra una API externa retiene su slot
    # del executor indefinidamente.
    "execution_timeout": timedelta(minutes=20),
}

# ─── Helpers ──────────────────────────────────────────────────────────────────


def _get_mindicador(sesion, endpoint: str) -> dict:
    """Llama a mindicador.cl y retorna JSON. Sin API Key requerida.

    Antes iba por urllib directo; ahora comparte cliente con el DAG de ARClim,
    así que hereda User-Agent, reintentos con backoff y reuso de conexión.
    """
    return get_json(sesion, f"{MINDICADOR_BASE}/{endpoint}", timeout=TIMEOUT)


def _parquets(s3, prefijo: str) -> list:
    """Lista los .parquet bajo un prefijo de bronze/, paginando.

    list_objects_v2 devuelve como mucho 1000 claves por llamada y no avisa de que
    truncó. Con escritura diaria una tabla pasa ese tope en unos meses, y a
    partir de ahí el conteo de la validación miente por lo bajo.
    """
    objetos = []
    for pagina in s3.get_paginator("list_objects_v2").paginate(Bucket="bronze", Prefix=prefijo):
        objetos += [o for o in pagina.get("Contents", []) if o["Key"].endswith(".parquet")]
    return objetos


def _existe_en_raw(s3, key: str) -> bool:
    """¿Ese archivo ya está descargado para esta fecha?"""
    try:
        s3.head_object(Bucket="raw", Key=key)
        return True
    except Exception:
        return False


def _s3_client():
    import boto3

    return boto3.client("s3", endpoint_url=MINIO_ENDPOINT)


def _subir_json(s3, key: str, data: dict) -> None:
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    s3.put_object(Bucket="raw", Key=key, Body=body, ContentType="application/json")
    log.info(f"  ✓ s3://raw/{key} ({len(body)} bytes)")


# ─── Task 1: Extraer indicadores ──────────────────────────────────────────────


def _fecha_ejecucion(context) -> str:
    """Fecha del run. En Airflow 3, los runs manuales sin logical_date
    no tienen 'ds' en el contexto."""
    if ds := context.get("ds"):
        return ds
    if logical := context.get("logical_date"):
        return logical.strftime("%Y-%m-%d")
    return datetime.now(UTC).strftime("%Y-%m-%d")


def extract_indicadores(**context):
    """
    Descarga todos los indicadores desde mindicador.cl
    y los guarda en MinIO raw/indicadores/fecha={ds}/*.json

    raw/ hace de cache: resumen.json se escribe al final, así que su presencia
    significa que la extracción de esa fecha ya terminó y no hay nada que pedir.
    El parámetro forzar_descarga lo ignora.

    Notas de frecuencia:
      - Diarios:   UF, Dólar, Euro, UTM, TPM → disponibles cada día hábil
      - Mensuales: IPC → se publica ~día 8 de cada mes (puede estar vacío)
    """
    s3 = _s3_client()
    fecha = _fecha_ejecucion(context)
    anio = fecha[:4]
    prefix = f"indicadores/fecha={fecha}"
    forzar = bool(context.get("params", {}).get("forzar_descarga", False))

    if not forzar and _existe_en_raw(s3, f"{prefix}/resumen.json"):
        log.info(f"→ raw/{prefix}/ ya está completo — se omite la descarga")
        log.info("  (para refrescar: disparar el DAG con forzar_descarga=true)")
        obj = s3.get_object(Bucket="raw", Key=f"{prefix}/resumen.json")
        return json.loads(obj["Body"].read().decode("utf-8"))

    sesion = crear_sesion()
    resumen = {"fecha": fecha, "fuente": "mindicador.cl", "indicadores": {}}
    errores = []

    # ── Snapshot diario ───────────────────────────────────────────────────────
    # No es crítico: es una foto de conveniencia, las series vienen aparte.
    log.info("→ Descargando snapshot diario...")
    try:
        snapshot = _get_mindicador(sesion, "")
    except ErrorAPI as e:
        log.warning(f"  ⚠ snapshot diario no disponible: {e}")
    else:
        _subir_json(s3, f"{prefix}/snapshot_diario.json", snapshot)
        log.info("  ✓ Snapshot diario OK")

    # ── Series anuales por indicador ──────────────────────────────────────────
    todos = INDICADORES_DIARIOS + INDICADORES_MENSUALES
    for nombre in todos:
        log.info(f"→ Descargando {nombre.upper()} {anio}...")
        try:
            data = _get_mindicador(sesion, f"{nombre}/{anio}")
        except ErrorAPI as e:
            # Un fallo de la API no se disfraza de "sin datos": se registra como
            # error y más abajo decide si tumba la tarea.
            log.error(f"  ✗ {nombre.upper()}: {e}")
            errores.append(nombre)
            resumen["indicadores"][nombre] = {"registros": 0, "error": str(e)}
            continue

        serie = data.get("serie", [])
        _subir_json(s3, f"{prefix}/{nombre}_{anio}.json", data)
        resumen["indicadores"][nombre] = {"registros": len(serie)}
        if len(serie) == 0 and nombre in INDICADORES_MENSUALES:
            log.warning(
                f"  ⚠ {nombre.upper()}: serie vacía (publicación mensual, aún no disponible)"
            )
        else:
            log.info(f"  ✓ {nombre.upper()}: {len(serie)} registros")

    # Un diario que no se pudo descargar es un fallo real. La validación aguas
    # abajo lo detectaría, pero mucho después y con un error menos claro.
    diarios_fallidos = [n for n in errores if n in INDICADORES_DIARIOS]
    if diarios_fallidos:
        raise ErrorAPI(
            "Indicadores diarios que no se pudieron descargar: "
            + ", ".join(n.upper() for n in diarios_fallidos)
        )

    # resumen.json va al final a propósito: es la marca de que esta fecha quedó
    # completa, y es lo que consulta el cache en la siguiente ejecución.
    _subir_json(s3, f"{prefix}/resumen.json", resumen)
    log.info("\n✓ Extracción completa")
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
        parquet = _parquets(s3, f"indicadores_{nombre}/")
        if not parquet:
            errores.append(f"✗ Sin Parquet en bronze/indicadores_{nombre}/")
        else:
            total_mb = sum(o["Size"] for o in parquet) / 1024 / 1024
            log.info(f"✓ bronze/indicadores_{nombre}/: {len(parquet)} archivos ({total_mb:.2f} MB)")

    # Validar indicadores mensuales — solo WARNING si no tienen datos
    for nombre in INDICADORES_MENSUALES:
        parquet = _parquets(s3, f"indicadores_{nombre}/")
        if not parquet:
            warnings.append(
                f"⚠ Sin Parquet en bronze/indicadores_{nombre}/ "
                f"(publicación mensual — puede no estar disponible aún)"
            )
        else:
            total_mb = sum(o["Size"] for o in parquet) / 1024 / 1024
            log.info(f"✓ bronze/indicadores_{nombre}/: {len(parquet)} archivos ({total_mb:.2f} MB)")

    # Mostrar warnings (no fallan el DAG)
    for w in warnings:
        log.info(w)

    # Solo fallar si hay errores en indicadores diarios
    if errores:
        for e in errores:
            log.info(e)
        raise ValueError(f"Validación fallida: {len(errores)} indicadores diarios sin datos")

    log.info("\n✓ Validación completada")
    if warnings:
        log.info(f"  {len(warnings)} advertencia(s) en indicadores mensuales (no crítico)")


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
    # Dos runs concurrentes escriben la misma fecha y duplican las filas. Pasó:
    # `airflow dags unpause` disparó el run programado del lunes mientras
    # load_example.sh disparaba el manual.
    max_active_runs=1,
    # raw/ hace de cache: por defecto no se vuelve a pedir lo ya descargado.
    params={"forzar_descarga": False},
    tags=["indicadores", "uf", "ipc", "dolar", "euro", "mindicador", "bronze"],
) as dag:
    t1 = PythonOperator(
        task_id="extract_indicadores",
        python_callable=extract_indicadores,
    )

    # La fecha viene por XCom desde extract_indicadores: es la misma que se usó
    # para escribir en raw/, y evita depender de `ds`, que no existe en los runs
    # manuales de Airflow 3.
    FECHA = "{{ ti.xcom_pull(task_ids='extract_indicadores')['fecha'] }}"

    t2 = SparkSubmitOperator(
        task_id="transform_bronze",
        conn_id="spark_default",
        # Sin esto el submit va con el nombre por defecto del operador,
        # "arrow-spark", que no dice nada en la UI de Spark.
        name="vektralforge-bronze-indicadores",
        application="/opt/spark/jobs/bronze_indicadores.py",
        application_args=[FECHA],
        # Sin --packages: delta-spark y delta-storage ya están en
        # /opt/spark/jars del cluster. Descargarlos desde Maven en cada
        # ejecución es innecesario y frágil.
        driver_memory="512m",
        executor_memory="512m",
        conf={
            "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
            "spark.sql.catalog.spark_catalog": "org.apache.spark.sql.delta.catalog.DeltaCatalog",
            "spark.hadoop.fs.s3a.endpoint": MINIO_ENDPOINT,
            # Las credenciales no van aquí: el job las resuelve desde el
            # entorno con EnvironmentVariableCredentialsProvider.
            "spark.hadoop.fs.s3a.path.style.access": "true",
            "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
            "spark.hadoop.fs.s3a.connection.ssl.enabled": "false",
            "spark.driver.maxResultSize": "128m",
            "spark.sql.shuffle.partitions": "2",
        },
        execution_timeout=timedelta(minutes=15),
    )

    t3 = PythonOperator(
        task_id="validar_bronze",
        python_callable=validar_bronze,
    )

    t1 >> t2 >> t3
