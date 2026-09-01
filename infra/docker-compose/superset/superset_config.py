"""Configuración de Superset para VektralForge.

Este archivo no existía, y su ausencia tenía dos consecuencias que nadie veía.

La imagen `apache/superset` no lee `DATABASE_URL`: su `config.py` fija
`SQLALCHEMY_DATABASE_URI` a un SQLite bajo `SUPERSET_HOME` y solo lo cambia
un `superset_config.py` en el `PYTHONPATH` (`/app/pythonpath`). El compose
pasaba `DATABASE_URL` apuntando a Postgres desde el principio y no lo leía
nadie, así que Superset guardaba sus dashboards en un SQLite dentro del
contenedor, sin volumen: cada `make dev-reset` los borraba.

Y el README anunciaba Redis como «caché de Superset». Superset lo esperaba por
`depends_on` y no lo contactaba nunca, porque las cachés vienen en `NullCache`
por defecto y solo se activan desde aquí.

Queda fuera `RESULTS_BACKEND`, que es el modo asíncrono de SQL Lab: exige un
worker de Celery, o sea otro contenedor. Cuando lo haya, va aquí.
"""

import os

SQLALCHEMY_DATABASE_URI = os.environ["DATABASE_URL"]

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
