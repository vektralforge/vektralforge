"""Tests unitarios del DAG de ejemplo."""

import pytest
from airflow.models import DagBag


@pytest.fixture(scope="module")
def dagbag():
    return DagBag(dag_folder="dags/", include_examples=False)


def test_dag_loads_without_errors(dagbag):
    assert "example_sqlserver_to_delta" in dagbag.dags
    assert len(dagbag.import_errors) == 0


def test_dag_has_correct_tasks(dagbag):
    dag = dagbag.dags["example_sqlserver_to_delta"]
    task_ids = {t.task_id for t in dag.tasks}
    assert task_ids == {"extract", "transform_and_write", "validate"}


def test_dag_has_no_cycles(dagbag):
    dag = dagbag.dags["example_sqlserver_to_delta"]
    assert dag.test_cycle() is None
