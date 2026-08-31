"""
dag_arclim_riesgo_climatico.py
DAG: arclim_riesgo_climatico_chile

Extrae datos de riesgo climático por comuna desde la API pública ARClim
del Ministerio del Medio Ambiente de Chile y los carga en Delta Lake bronze.

API: https://arclim.mma.gob.cl/atlas/api/
Sin API Key requerida.

Tablas Delta Lake generadas:
  - bronze/arclim_comunas/         ← atributos y riesgo climático por comuna
  - bronze/arclim_indicadores/     ← catálogo de indicadores disponibles
  - bronze/arclim_series/          ← series de tiempo por indicador/comuna

Schedule: semanal (lunes 06:00 AM) — los datos no cambian diariamente

raw/ es la zona de aterrizaje y también el cache: lo ya descargado para una
fecha no se vuelve a pedir. Para refrescar de verdad, disparar el DAG con
forzar_descarga=true.
"""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime, timedelta

from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.providers.standard.operators.python import PythonOperator

from http_publico import PAUSA_ENTRE_LLAMADAS, ErrorAPI, crear_sesion, get_json

# ── Configuración ─────────────────────────────────────────────────────────────
ARCLIM_BASE = "https://arclim.mma.gob.cl/api"
# Sin valores por defecto: unas credenciales silenciosamente incorrectas
# fallan mucho después y con un error de S3 que no señala la causa.
MINIO_ENDPOINT = os.environ["MINIO_ENDPOINT"]
# Las credenciales se quedan en el entorno: boto3 y el provider de S3A las
# resuelven desde AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY. No se pasan por
# `conf` al SparkSubmitOperator: ahí acabarían en la línea de comandos del
# proceso y en la UI del driver.
for _var in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
    if _var not in os.environ:
        raise RuntimeError(f"Falta la variable de entorno {_var!r}")
TIMEOUT = 60  # segundos por request


# Indicadores climáticos que ARClim sirve hoy. Se piden a /datos/ (atributos por
# comuna) y a /series/ (series de tiempo por comuna capital).
INDICADORES = [
    "hot_days",  # Días con temperatura > 30°C
    "consecutive_days_over_25C",  # Olas de calor > 25°C
    "frost_days",  # Días con helada (temperatura < 0°C)
    "mean_temperature",  # Temperatura media anual
]

# ARClim NO sirve estos: devuelven 500 en /datos/ y en /series/, en las tres
# variantes (present, future, delta) y para cualquier comuna. Comprobado el
# 2026-08-31 atributo por atributo contra la API.
#
# Merece quedar escrito porque explica dos rarezas del código anterior.
# `total_precipitation` estaba en la lista y su único efecto era envenenar la
# petición de /datos/ —basta un atributo suyo para que falle entera— y gastar 13
# llamadas condenadas en /series/. Que la extracción funcionara se debía a que el
# recorte a los 10 primeros atributos lo dejaba fuera por casualidad, no por
# diseño. Y `dry_days` estaba documentado como "solo disponible en /datos/", que
# tampoco es cierto: no está disponible en ninguno.
INDICADORES_NO_DISPONIBLES = ("dry_days", "total_precipitation")

# Comunas capitales regionales por código ARClim
COMUNAS_CAPITALES = {
    "13101": "Santiago",
    "1101": "Arica",
    "2101": "Antofagasta",
    "3101": "Copiapó",
    "4101": "La Serena",
    "5101": "Valparaíso",
    "7101": "Talca",
    "8101": "Concepción",
    "9101": "Temuco",
    "10101": "Puerto Montt",
    "11101": "Coyhaique",
    "12101": "Punta Arenas",
    "14101": "Valdivia",
}

default_args = {
    "owner": "vektralforge",
    "retries": 0,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=30),
}


def _fecha_ejecucion(context) -> str:
    """Fecha del run. En Airflow 3, los runs manuales sin logical_date
    no tienen 'ds' en el contexto."""
    if ds := context.get("ds"):
        return ds
    if logical := context.get("logical_date"):
        return logical.strftime("%Y-%m-%d")
    return datetime.now(UTC).strftime("%Y-%m-%d")


def _series_traen_modelos(payload) -> bool:
    """¿El archivo de series guarda las series de los modelos?

    El formato anterior guardaba p10/p90 ya digeridos —y mal— sin las series por
    modelo. Un archivo así en el cache haría que la tabla se escribiera sin banda
    de incertidumbre, así que se trata como cache miss y se vuelve a descargar.
    """
    for info in payload.values():
        for serie in info.get("indicadores", {}).values():
            if "series" not in serie:
                return False
    return True


def _existe_en_raw(s3, key: str) -> bool:
    """¿Ese archivo ya está descargado para esta fecha?"""
    try:
        s3.head_object(Bucket="raw", Key=key)
        return True
    except Exception:
        return False


def extract_arclim(**context):
    """
    Extrae datos de ARClim API y los guarda en raw/arclim/fecha={ds}/:
    1. indicadores_climaticos.json   — catálogo completo de indicadores
    2. riesgo_comunas.json           — riesgo por las 346 comunas de Chile
    3. series_comunas_capitales.json — series temporales 1970-2070

    Cada archivo se salta si ya existe para esa fecha, así que reejecutar el DAG
    mientras se itera sobre el transform no cuesta ni una llamada a la API. El
    parámetro forzar_descarga ignora el cache.
    """
    import boto3
    from botocore.client import Config

    ds = _fecha_ejecucion(context)
    prefix = f"arclim/fecha={ds}"
    forzar = bool(context.get("params", {}).get("forzar_descarga", False))

    s3 = boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        config=Config(signature_version="s3v4"),
    )
    sesion = crear_sesion()
    llamadas = 0

    def cacheado(nombre, forma_valida=None):
        if forzar or not _existe_en_raw(s3, f"{prefix}/{nombre}"):
            return False
        if forma_valida is not None:
            try:
                obj = s3.get_object(Bucket="raw", Key=f"{prefix}/{nombre}")
                if not forma_valida(json.loads(obj["Body"].read().decode("utf-8"))):
                    print(f"  · {nombre} está en raw/ con un formato antiguo — se vuelve a pedir")
                    return False
            except Exception as e:
                print(f"  · no se pudo leer {nombre} del cache ({e}) — se vuelve a pedir")
                return False
        print(f"  · {nombre} ya está en raw/{prefix}/ — no se vuelve a pedir")
        return True

    def upload(data, key):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        s3.put_object(Bucket="raw", Key=f"{prefix}/{key}", Body=body)
        print(f"  ✓ raw/{prefix}/{key} ({len(body):,} bytes)")

    # ── 1. Catálogo de indicadores ────────────────────────────────────────────
    # Crítico: sin él no hay tabla arclim_indicadores, así que un fallo aquí
    # tumba la tarea en vez de dejar el pipeline a medias sin avisar.
    if not cacheado("indicadores_climaticos.json"):
        print("→ Descargando catálogo de indicadores climáticos...")
        indicadores = get_json(sesion, f"{ARCLIM_BASE}/indicadores_climaticos", timeout=TIMEOUT)
        llamadas += 1
        upload(indicadores, "indicadores_climaticos.json")
        print(f"  ✓ {len(indicadores.get('data', []))} indicadores disponibles")

    # ── 2. Riesgo climático por comunas ───────────────────────────────────────
    if not cacheado("riesgo_comunas.json"):
        print("→ Descargando riesgo climático por comunas...")
        atributos = ["NOM_COMUNA", "REGION", "PROVINCIA"]
        for ind in INDICADORES:
            atributos += [
                f"$CLIMA${ind}$annual$present",
                f"$CLIMA${ind}$annual$future",
                f"$CLIMA${ind}$annual$delta",
            ]

        # Los 15 atributos caben en una sola petición. El código anterior
        # recortaba a los 10 primeros —el comentario hablaba de partir en dos
        # requests y la segunda nunca se escribió—, y la tabla nacía con 7
        # columnas climáticas de las 12 posibles: faltaban los 4 delta y un
        # future. El 500 que motivó aquel recorte no venía del tamaño sino de
        # total_precipitation; ver INDICADORES_NO_DISPONIBLES.
        try:
            payload = get_json(
                sesion,
                f"{ARCLIM_BASE}/datos/comunas/json/",
                params={"attributes": ",".join(atributos)},
                timeout=TIMEOUT,
            )
            llamadas += 1
        except ErrorAPI as e:
            # No es crítico: la validación lo trata como advertencia y el job de
            # Spark escribe igual las otras dos tablas.
            print(f"  ⚠ riesgo_comunas no disponible: {e}")
        else:
            upload(payload, "riesgo_comunas.json")
            contenido = payload.get("data", payload)
            print(
                f"  ✓ {len(contenido.get('index', []))} comunas × "
                f"{len(contenido.get('columns', []))} atributos"
            )

    # ── 3. Series de tiempo para comunas capitales ────────────────────────────
    if not cacheado("series_comunas_capitales.json", _series_traen_modelos):
        total = len(COMUNAS_CAPITALES) * len(INDICADORES)
        print(f"→ Descargando series de tiempo ({total} llamadas, espaciadas)...")
        series_all = {}
        fallos = []
        for cod, nombre in COMUNAS_CAPITALES.items():
            series_all[cod] = {"nombre": nombre, "indicadores": {}}
            for ind in INDICADORES:
                url_s = f"{ARCLIM_BASE}/series/{ind}/comunas/{cod}/annual/ssp585"
                try:
                    serie = get_json(sesion, url_s, timeout=TIMEOUT, pausa=PAUSA_ENTRE_LLAMADAS)
                    llamadas += 1
                except ErrorAPI as e:
                    fallos.append(f"{nombre}/{ind}: {e}")
                    continue
                # Se guardan las series por modelo, no percentiles digeridos:
                # raw/ debe ser fiel a la API y la banda la calcula el job.
                # `pseries` NO sirve para esto: tiene forma 20×11 —un modelo por
                # fila, once percentiles por columna—, no once series anuales.
                series_all[cod]["indicadores"][ind] = {
                    "years": serie.get("years", []),
                    "mean": serie.get("mean", []),
                    "series": serie.get("series", []),
                    "gcms": serie.get("gcms", []),
                }

        con_datos = sum(len(v["indicadores"]) for v in series_all.values())
        if con_datos == 0:
            raise ErrorAPI(f"Ninguna de las {total} series se pudo descargar")

        # Un indicador que falla en TODAS las comunas no es un fallo pasajero:
        # es que /series/ no lo sirve. Merece un mensaje accionable en vez de
        # quedar diluido entre los fallos sueltos, que es como total_precipitation
        # pasó inadvertido hasta ahora.
        for ind in INDICADORES:
            if not any(ind in v["indicadores"] for v in series_all.values()):
                print(
                    f"  ⚠ '{ind}' falló en las {len(COMUNAS_CAPITALES)} comunas — "
                    "si es permanente, moverlo a INDICADORES_NO_DISPONIBLES"
                )

        if fallos:
            print(f"  ⚠ {len(fallos)} de {total} series fallaron:")
            for f in fallos[:5]:
                print(f"      {f}")
        print(f"  ✓ {con_datos}/{total} series descargadas")
        upload(series_all, "series_comunas_capitales.json")

    print(f"\n✓ Extracción ARClim completada → raw/{prefix}/  ({llamadas} llamadas a la API)")

    # transform_bronze necesita la misma fecha con la que se escribió raw/.
    return {"fecha": ds, "prefix": prefix}


def validar_arclim(**context):
    """Valida que los archivos raw existen y tienen datos mínimos."""
    import boto3
    from botocore.client import Config

    ds = _fecha_ejecucion(context)
    prefix = f"arclim/fecha={ds}"

    s3 = boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        config=Config(signature_version="s3v4"),
    )

    errores = []
    advertencias = []

    # Archivos críticos (ERROR si faltan)
    for archivo in [
        "indicadores_climaticos.json",
        "series_comunas_capitales.json",
    ]:
        try:
            obj = s3.get_object(Bucket="raw", Key=f"{prefix}/{archivo}")
            size = obj["ContentLength"]
            print(f"  ✓ {archivo} ({size:,} bytes)")
        except Exception as e:
            errores.append(f"✗ {archivo}: {e}")

    # riesgo_comunas.json — WARNING si falta (URL con $ puede fallar)
    try:
        obj = s3.get_object(Bucket="raw", Key=f"{prefix}/riesgo_comunas.json")
        data = json.loads(obj["Body"].read())
        n = len(data.get("index", []))
        if n < 300:
            advertencias.append(f"Solo {n} comunas (esperado ~346)")
        else:
            print(f"  ✓ {n} comunas con datos de riesgo")
    except Exception as e:
        advertencias.append(f"⚠ riesgo_comunas.json no disponible: {e}")
        print("  ⚠ riesgo_comunas.json: no disponible (continuando)")

    # Verificar series
    try:
        obj = s3.get_object(Bucket="raw", Key=f"{prefix}/series_comunas_capitales.json")
        data = json.loads(obj["Body"].read())
        comunas_con_series = len([v for v in data.values() if v.get("indicadores")])
        print(f"  ✓ Series de tiempo: {comunas_con_series} comunas capitales")
    except Exception as e:
        errores.append(f"Error validando series: {e}")

    for adv in advertencias:
        print(f"  ⚠ {adv}")

    if errores:
        raise ValueError("Validación ARClim fallida:\n" + "\n".join(errores))

    print(f"\n✓ Validación completada ({len(advertencias)} advertencias)")


# ── DAG ───────────────────────────────────────────────────────────────────────
with DAG(
    dag_id="arclim_riesgo_climatico_chile",
    description=(
        "Extrae indicadores de riesgo climático por comuna desde ARClim "
        "(Ministerio del Medio Ambiente de Chile). Sin API Key requerida. "
        "Datos históricos 1980-2010 y proyecciones 2035-2065 (SSP5-8.5/SSP2-4.5)."
    ),
    schedule="0 6 * * MON",
    start_date=datetime(2026, 7, 1),
    catchup=False,
    # Dos runs concurrentes escriben la misma fecha y duplican las filas. Pasó:
    # `airflow dags unpause` disparó el run programado del lunes mientras
    # load_example.sh disparaba el manual.
    max_active_runs=1,
    # raw/ hace de cache: por defecto no se vuelve a pedir lo ya descargado.
    params={"forzar_descarga": False},
    default_args=default_args,
    tags=["arclim", "clima", "mma", "chile", "bronze"],
) as dag:
    extract = PythonOperator(
        task_id="extract_arclim",
        python_callable=extract_arclim,
    )

    # La fecha viaja por XCom desde extract_arclim: es la misma con la que se
    # escribió en raw/, y evita depender de {{ ds }}, que no existe en los runs
    # manuales de Airflow 3.
    FECHA = "{{ ti.xcom_pull(task_ids='extract_arclim')['fecha'] }}"

    transform = SparkSubmitOperator(
        task_id="transform_bronze",
        conn_id="spark_default",
        # Sin esto el submit va con el nombre por defecto del operador,
        # "arrow-spark", que no dice nada en la UI de Spark.
        name="vektralforge-bronze-arclim",
        application="/opt/spark/jobs/bronze_arclim.py",
        application_args=[FECHA],
        # Sin --packages: delta-spark y delta-storage ya están en
        # /opt/spark/jars del cluster y en el pyspark del contenedor de Airflow.
        driver_memory="512m",
        executor_memory="512m",
        conf={
            "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
            "spark.sql.catalog.spark_catalog": ("org.apache.spark.sql.delta.catalog.DeltaCatalog"),
            "spark.hadoop.fs.s3a.endpoint": MINIO_ENDPOINT,
            # Las credenciales no van aquí: el job las resuelve desde el
            # entorno con EnvironmentVariableCredentialsProvider.
            "spark.hadoop.fs.s3a.path.style.access": "true",
            "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
            "spark.hadoop.fs.s3a.connection.ssl.enabled": "false",
            "spark.driver.maxResultSize": "128m",
            "spark.sql.shuffle.partitions": "2",
        },
        execution_timeout=timedelta(minutes=20),
    )

    validar = PythonOperator(
        task_id="validar_bronze",
        python_callable=validar_arclim,
    )

    extract >> transform >> validar
