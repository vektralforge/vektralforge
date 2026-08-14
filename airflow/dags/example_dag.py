"""
example_dag.py — DAG de ejemplo: SQL Server → Delta Lake vía Spark.

Rol de Spark en este DAG:
  - Spark ESCRIBE en Delta Lake con semántica ACID (MERGE/INSERT).
  - Trino solo se usa para consultar los datos resultantes, no para escribir.
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator

DEFAULT_ARGS = {
    "owner": "alephserver",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="example_sqlserver_to_delta",
    description="Carga incremental SQL Server → Delta Lake (Spark escribe ACID)",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="0 6 * * *",
    catchup=False,
    tags=["example", "sqlserver", "delta", "spark-writes"],
) as dag:

    def extract(**context):
        """Extrae datos desde SQL Server. Credenciales desde OpenBao."""
        # TODO: leer credenciales de OpenBao via hvac
        # import hvac
        # client = hvac.Client(url=os.getenv("OPENBAO_ADDR"))
        # secret = client.secrets.kv.read_secret("sqlserver/credentials")
        print("Extrayendo datos de SQL Server con credenciales desde OpenBao...")

    def transform_and_write(**context):
        """
        Transforma y escribe en Delta Lake via Spark.
        IMPORTANTE: Spark es el motor de escritura ACID. Trino NO escribe Delta.
        """
        # TODO: SparkSubmitOperator con spark/jobs/example_transform.py
        # El job Spark hará un MERGE INTO sobre la tabla Delta (operación ACID)
        print("Spark: escribiendo en Delta Lake con MERGE ACID...")

    def validate(**context):
        """Valida calidad de datos con Great Expectations."""
        print("Great Expectations: validando schema, nulos y rangos...")

    t_extract = PythonOperator(task_id="extract", python_callable=extract)
    t_transform = PythonOperator(task_id="transform_and_write", python_callable=transform_and_write)
    t_validate = PythonOperator(task_id="validate", python_callable=validate)

    t_extract >> t_transform >> t_validate
