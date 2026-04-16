"""
test_dag_bronze_ejemplo.py
Tests unitarios del DAG bronze_clientes_ejemplo.
"""

import pytest
from airflow.models import DagBag


@pytest.fixture(scope="module")
def dagbag():
    return DagBag(dag_folder="dags/", include_examples=False)


def test_dag_carga_sin_errores(dagbag):
    """El DAG debe cargarse sin errores de importación."""
    assert "bronze_clientes_ejemplo" in dagbag.dags
    assert len(dagbag.import_errors) == 0


def test_dag_tiene_tres_tasks(dagbag):
    """El DAG debe tener exactamente 3 tasks."""
    dag = dagbag.dags["bronze_clientes_ejemplo"]
    assert len(dag.tasks) == 3
    task_ids = {t.task_id for t in dag.tasks}
    assert task_ids == {"generar_y_subir_raw", "transformar_a_bronze", "validar_bronze"}


def test_dag_orden_correcto(dagbag):
    """Las tasks deben ejecutarse en el orden correcto."""
    dag = dagbag.dags["bronze_clientes_ejemplo"]
    t1 = dag.get_task("generar_y_subir_raw")
    t2 = dag.get_task("transformar_a_bronze")
    t3 = dag.get_task("validar_bronze")

    assert t2.task_id in {t.task_id for t in t1.downstream_list}
    assert t3.task_id in {t.task_id for t in t2.downstream_list}


def test_dag_sin_ciclos(dagbag):
    """El DAG no debe tener ciclos."""
    dag = dagbag.dags["bronze_clientes_ejemplo"]
    assert dag.test_cycle() is None


def test_dag_schedule_manual(dagbag):
    """El DAG debe tener schedule None (ejecución manual)."""
    dag = dagbag.dags["bronze_clientes_ejemplo"]
    assert dag.schedule_interval is None
