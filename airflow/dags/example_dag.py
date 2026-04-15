"""
example_dag.py
DAG de ejemplo que carga datos desde SQL Server hacia Delta Lake en MinIO.
Referencia para nuevos DAGs en lakeforge.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator

# ─── configuración por defecto ────────────────────────────────────────────────
DEFAULT_ARGS = {
    "owner": "alephserver",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

# ─── DAG ─────────────────────────────────────────────────────────────────────
with DAG(
    dag_id="example_sqlserver_to_delta",
    description="Carga incremental SQL Server → Delta Lake (ejemplo)",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="0 6 * * *",  # Diario a las 06:00
    catchup=False,
    tags=["example", "sqlserver", "delta"],
) as dag:

    def extract(**context):
        """Extrae datos desde SQL Server."""
        # TODO: implementar con SQLToS3Operator o pandas + pyodbc
        print("Extrayendo datos de SQL Server...")

    def transform(**context):
        """Transforma y escribe en Delta Lake via Spark."""
        # TODO: invocar SparkSubmitOperator con spark/jobs/transform_example.py
        print("Transformando y escribiendo en Delta Lake...")

    def validate(**context):
        """Valida calidad de datos con Great Expectations."""
        # TODO: ejecutar checkpoint de Great Expectations
        print("Validando calidad de datos...")

    t_extract   = PythonOperator(task_id="extract",   python_callable=extract)
    t_transform = PythonOperator(task_id="transform", python_callable=transform)
    t_validate  = PythonOperator(task_id="validate",  python_callable=validate)

    t_extract >> t_transform >> t_validate
