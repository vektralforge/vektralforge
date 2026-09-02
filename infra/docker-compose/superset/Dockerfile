# VektralForge — Superset
#
# 3.1.3 era de febrero de 2024 y arrastraba CVEs posteriores. Es el §2.2.

FROM apache/superset:6.1.0

# ── Driver de Trino ──────────────────────────────────────────────────────────
#
# Se instala con `uv pip install` apuntando al venv, NO con el `pip` del PATH.
# La diferencia no es cosmética:
#
#   imagen 3.1.3 → pip: /usr/local/lib/python3.10   python: /usr/local     (mismo)
#   imagen 6.1.0 → pip: /usr/local/lib/python3.10   python: /app/.venv     (distinto)
#
# Desde la 5.0 las imágenes de Superset corren desde un venv creado por uv, y
# `/app/.venv/bin/pip` ni siquiera existe. Un `pip install` a secas dejaría el
# driver en /usr/local/lib, donde Superset no mira: la imagen se construiría sin
# un solo error y el fallo aparecería después como un problema de conexión a
# Trino, sin nada que apuntara a la causa.
#
# La versión va fijada (antes era `pip install "trino[sqlalchemy]"` a secas, la
# otra mitad del §2.3): así una versión nueva del driver no entra sin revisión.
# psycopg2 va aquí porque la 6.1.0 YA NO LO TRAE. La 3.1.3 lo incluía; desde
# entonces Superset movió los drivers de base de datos a extras opcionales y la
# imagen lean no los lleva. Sin él, gunicorn arranca, crea la app, llega a
# `create_engine` sobre la URI de Postgres y muere con ModuleNotFoundError — en
# bucle de reinicio, sin que la construcción de la imagen haya dicho nada.
ARG TRINO_VERSION=0.339.0
ARG PSYCOPG2_VERSION=2.9.11

USER root
RUN uv pip install --python /app/.venv/bin/python \
        "trino[sqlalchemy]==${TRINO_VERSION}" \
        "psycopg2-binary==${PSYCOPG2_VERSION}" && \
    rm -rf /root/.cache/uv

USER superset

# La imagen deja /app/pythonpath vacío y solo importa `superset_config` si está
# ahí. Sin este archivo no se lee la conexión a Postgres —los dashboards
# acabarían en un SQLite sin volumen— y las cachés quedan en NullCache.
COPY superset_config.py /app/pythonpath/superset_config.py

# Verificación en tiempo de build, con el intérprete que usa Superset y NO con el
# `python` que toque estar en el PATH.
#
# La comprobación central es `create_engine` sobre la URI que arma la propia
# configuración: eso importa el DBAPI que la URI exija, sea cual sea. La primera
# versión de este Dockerfile comprobaba solo el driver de Trino —lo que yo
# añadía— y no vio que la 6.1.0 había dejado de traer psycopg2: la imagen se
# construyó limpia y el contenedor entró en bucle de reinicio.
#
# Preguntar por lo que la configuración necesita, en vez de por lo que uno
# instaló, es lo que hace que esta guarda siga sirviendo cuando cambie la URI.
RUN DATABASE_PASSWORD=comprobacion-de-build \
    /app/.venv/bin/python -c "\
import sys; sys.path.insert(0, '/app/pythonpath');\
import superset_config as c;\
import sqlalchemy;\
from sqlalchemy.dialects import registry;\
assert c.CACHE_CONFIG['CACHE_TYPE'] == 'RedisCache';\
assert c.DATA_CACHE_CONFIG['CACHE_REDIS_DB'] == 2;\
e = sqlalchemy.create_engine(c.SQLALCHEMY_DATABASE_URI);\
print(f'  metadatos: {e.dialect.name}+{e.dialect.driver} · DBAPI {e.dialect.dbapi.__name__}');\
d = registry.load('trino');\
import trino;\
print(f'  datos:     trino {trino.__version__} · dialecto {d.__name__}');\
print(f'  sqlalchemy {sqlalchemy.__version__}')"
