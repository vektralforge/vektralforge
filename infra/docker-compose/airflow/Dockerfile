FROM apache/airflow:2.9.1-python3.12

# ── OpenLineage provider para Airflow 2.9.x ──────────────────────────────────
# apache-airflow-providers-openlineage >= 2.x requiere Airflow 2.11+
# Para Airflow 2.9.x usar 1.10.0 (última versión compatible)
USER airflow
RUN pip install \
    "openlineage-python==1.47.1" \
    "apache-airflow-providers-openlineage==1.10.0" \
    --quiet
