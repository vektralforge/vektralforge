"""
test_example_dag.py
Tests unitarios del DAG de ejemplo.
Ejecutar: cd airflow && pytest tests/ -v
"""
import pytest
from airflow.models import DagBag


@pytest.fixture(scope="module")
def dagbag():
    return DagBag(dag_folder="dags/", include_examples=False)


def test_dag_loads_without_errors(dagbag):
    """El DAG debe cargarse sin errores de importación."""
    assert "example_sqlserver_to_delta" in dagbag.dags
    assert len(dagbag.import_errors) == 0


def test_dag_has_correct_tasks(dagbag):
    """El DAG debe tener las tareas definidas."""
    dag = dagbag.dags["example_sqlserver_to_delta"]
    task_ids = {t.task_id for t in dag.tasks}
    assert task_ids == {"extract", "transform", "validate"}


def test_dag_has_no_cycles(dagbag):
    """El DAG no debe tener ciclos."""
    dag = dagbag.dags["example_sqlserver_to_delta"]
    assert dag.test_cycle() is None


def test_dag_schedule(dagbag):
    """El DAG debe tener schedule diario."""
    dag = dagbag.dags["example_sqlserver_to_delta"]
    assert dag.schedule_interval == "0 6 * * *"
