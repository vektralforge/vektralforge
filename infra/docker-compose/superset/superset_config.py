"""Configuración de Superset para VektralForge.

Este archivo no existía, y su ausencia tenía dos consecuencias que nadie veía.

La imagen `apache/superset` no lee ninguna variable de conexión: su `config.py`
fija `SQLALCHEMY_DATABASE_URI` a un SQLite bajo `SUPERSET_HOME` y solo lo cambia
un `superset_config.py` en el `PYTHONPATH` (`/app/pythonpath`). El compose
pasaba un `DATABASE_URL` apuntando a Postgres desde el principio y no lo leía
nadie, así que Superset guardaba sus dashboards en un SQLite dentro del
contenedor, sin volumen: cada `make dev-reset` los borraba.

Y el README anunciaba Redis como «caché de Superset». Superset lo esperaba por
`depends_on` y no lo contactaba nunca, porque las cachés vienen en `NullCache`
por defecto y solo se activan desde aquí.

Queda fuera `RESULTS_BACKEND`, que es el modo asíncrono de SQL Lab: exige un
worker de Celery, o sea otro contenedor. Cuando lo haya, va aquí.
"""

import os
from pathlib import Path
from urllib.parse import quote


def _password() -> str:
    """La contraseña de Postgres, leída del secreto montado por compose.

    Antes llegaba dentro de `DATABASE_URL`, es decir, como variable de entorno:
    visible en `docker inspect` y en /proc/<pid>/environ de cualquier proceso
    del contenedor. Ahora viaja como archivo y la cadena se arma aquí.

    Se acepta todavía DATABASE_PASSWORD para no romper a quien tenga un compose
    antiguo, pero el archivo manda.
    """
    ruta = os.environ.get("DATABASE_PASSWORD_FILE")
    if ruta:
        try:
            return Path(ruta).read_text(encoding="utf-8").strip("\n")
        except OSError as e:
            raise RuntimeError(
                f"No se puede leer el secreto en {ruta}: {e}. "
                "Lo monta docker-compose.yml desde el bloque secrets:; "
                "requiere Compose 2.20 o superior para el origen environment:."
            ) from e
    try:
        return os.environ["DATABASE_PASSWORD"]
    except KeyError:
        raise RuntimeError(
            "Faltan DATABASE_PASSWORD_FILE y DATABASE_PASSWORD. El compose "
            "monta el secreto en /run/secrets/postgres_password."
        ) from None


# quote() sobre usuario y contraseña: la cadena es una URL, y un '@', ':' o '/'
# dentro de la contraseña partiría el netloc en el sitio equivocado.
SQLALCHEMY_DATABASE_URI = (
    "postgresql+psycopg2://"
    f"{quote(os.environ.get('DATABASE_USER', 'vektralforge'), safe='')}"
    f":{quote(_password(), safe='')}"
    f"@{os.environ.get('DATABASE_HOST', 'postgres')}"
    f":{os.environ.get('DATABASE_PORT', '5432')}"
    f"/{os.environ.get('DATABASE_DB', 'superset')}"
)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

# Metadatos de la aplicación: listas de dashboards, permisos, miniaturas.
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_HOST": REDIS_HOST,
    "CACHE_REDIS_PORT": REDIS_PORT,
    "CACHE_REDIS_DB": 1,
}

# Resultados de las consultas que alimentan los gráficos. Timeout más largo:
# los datos de bronze se reescriben una vez al día, no a cada minuto.
DATA_CACHE_CONFIG = {
    **CACHE_CONFIG,
    "CACHE_DEFAULT_TIMEOUT": 3600,
    "CACHE_KEY_PREFIX": "superset_datos_",
    "CACHE_REDIS_DB": 2,
}
