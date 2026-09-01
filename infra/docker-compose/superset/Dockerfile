FROM apache/superset:3.1.3

# Instalar driver Trino para conectar a Delta Lake via Trino
USER root
RUN pip install "trino[sqlalchemy]" --quiet
USER superset

# La imagen deja /app/pythonpath vacío y solo importa `superset_config` si
# está ahí. Sin este archivo, DATABASE_URL no se lee y las cachés quedan en
# NullCache.
COPY superset_config.py /app/pythonpath/superset_config.py
