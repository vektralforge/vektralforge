FROM apache/superset:3.1.3

# Instalar driver Trino para conectar a Delta Lake via Trino
USER root
RUN pip install "trino[sqlalchemy]" --quiet
USER superset
