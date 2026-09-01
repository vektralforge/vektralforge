"""Cliente HTTP compartido por los DAGs que consumen APIs públicas.

Las dos fuentes del proyecto son servicios públicos y gratuitos —mindicador.cl
y la API ARClim del Ministerio del Medio Ambiente—. Nadie paga por ellas y
nadie nos debe disponibilidad, así que el cliente se identifica, reintenta con
backoff y espacia sus llamadas. La diferencia entre un consumidor tolerable y
uno bloqueado suele ser exactamente eso.

Vive en plugins/ y no en dags/ porque Airflow 3 añade la carpeta de plugins al
sys.path pero NO la de DAGs: un `from http_publico import ...` desde un archivo
de dags/ falla con ModuleNotFoundError dentro del contenedor. Comprobado contra
el DagBag de Airflow 3.3.0, no deducido de la documentación.
"""

from __future__ import annotations

import time

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Un User-Agent identificable y con URL de contacto es lo que hace que un
# operador te ponga en una lista blanca en vez de bloquearte. El valor por
# defecto de requests es "python-requests/2.x", que no dice nada.
USER_AGENT = "vektralforge/1.0 (+https://github.com/vektralforge/vektralforge)"

# Pausa entre llamadas de un mismo lote. Con 65 series son ~33 s de espera
# repartidos, muy por debajo del execution_timeout de la tarea.
PAUSA_ENTRE_LLAMADAS = 0.5

# Se reintentan 429 y 5xx; los 4xx del cliente no, porque reintentar un 404 no
# lo arregla. respect_retry_after_header hace que un Retry-After del servidor
# mande sobre nuestro backoff: si la API dice cuánto esperar, se le hace caso.
REINTENTOS = Retry(
    total=3,
    backoff_factor=1.5,
    status_forcelist=(429, 500, 502, 503, 504),
    allowed_methods=("GET",),
    respect_retry_after_header=True,
    raise_on_status=False,
)


class ErrorAPI(RuntimeError):
    """La API falló.

    Deliberadamente distinto de "la API respondió que no hay datos": una serie
    vacía es un hecho del mundo, un 503 es un problema nuestro. Confundirlos es
    lo que hacía que un 429 desapareciera como si no hubiera datos.
    """


def crear_sesion() -> requests.Session:
    """Sesión con User-Agent, reintentos y reuso de conexión."""
    sesion = requests.Session()
    sesion.headers["User-Agent"] = USER_AGENT
    adaptador = HTTPAdapter(max_retries=REINTENTOS, pool_connections=4, pool_maxsize=4)
    sesion.mount("https://", adaptador)
    sesion.mount("http://", adaptador)
    return sesion


def get_json(sesion, url, *, params=None, timeout=60, pausa=0.0):
    """GET que devuelve JSON o lanza ErrorAPI.

    Nunca devuelve None: quien llama decide si un fallo es tolerable, y para eso
    necesita poder distinguirlo de una respuesta legítimamente vacía.
    """
    try:
        respuesta = sesion.get(url, params=params, timeout=timeout)
        respuesta.raise_for_status()
        datos = respuesta.json()
    except requests.RequestException as e:
        raise ErrorAPI(f"{url}: {type(e).__name__}: {e}") from e
    except ValueError as e:
        raise ErrorAPI(f"{url}: la respuesta no es JSON válido: {e}") from e

    if pausa:
        time.sleep(pausa)
    return datos
