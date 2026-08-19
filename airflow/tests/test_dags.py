"""
Tests de los DAGs de VektralForge.

Cada test aquí corresponde a un fallo que ya ocurrió en el proyecto. No son
pruebas hipotéticas: son la red que evita repetir errores concretos.

  · Un `import boto3a` con typo pasó el lint y rompió un DAG en ejecución.
  · Un `xcom_pull(task_ids='extract_indicadores')` en el DAG de ARClim apuntaba
    a una tarea de otro DAG; el pull habría devuelto None.
  · `context["ds"]` lanzó KeyError: Airflow 3 no lo provee en runs manuales.
  · `schedule_interval` dejó de existir en Airflow 3 y el DAG no se parseaba.
"""

import re
from datetime import UTC

import pytest

DAGS_ESPERADOS = {
    "indicadores_financieros_chile",
    "arclim_riesgo_climatico_chile",
}


# ── Parseo ────────────────────────────────────────────────────────────────────


def test_sin_errores_de_import(dagbag):
    """Ningún archivo de dags/ falla al importarse.

    Es el test más barato y el que más veces habría avisado: un typo en un
    import o una API eliminada en Airflow 3 hacen que el scheduler descarte el
    DAG en silencio.
    """
    assert not dagbag.import_errors, "Errores de import:\n" + "\n".join(
        f"  {archivo}: {error}" for archivo, error in dagbag.import_errors.items()
    )


def test_dags_esperados_presentes(dagbag):
    encontrados = set(dagbag.dag_ids)
    faltantes = DAGS_ESPERADOS - encontrados
    assert not faltantes, f"DAGs no cargados: {faltantes}"


# ── Referencias entre tareas ──────────────────────────────────────────────────


@pytest.mark.parametrize("dag_id", sorted(DAGS_ESPERADOS))
def test_xcom_pull_apunta_a_tareas_del_mismo_dag(dagbag, dag_id):
    """Todo xcom_pull debe referirse a una tarea que existe en su propio DAG.

    El DAG de ARClim tiraba de 'extract_indicadores', que pertenece al DAG de
    indicadores financieros. El pull habría devuelto None y el acceso al
    diccionario habría lanzado TypeError en ejecución, no al parsear.
    """
    dag = dagbag.dags[dag_id]
    tareas = set(dag.task_ids)
    patron = re.compile(r"xcom_pull\(\s*task_ids\s*=\s*['\"]([^'\"]+)['\"]")

    problemas = []
    for tarea in dag.tasks:
        for campo in tarea.template_fields:
            valor = getattr(tarea, campo, None)
            for texto in _cadenas(valor):
                for referida in patron.findall(texto):
                    if referida not in tareas:
                        problemas.append(f"{tarea.task_id}.{campo} → '{referida}'")

    assert not problemas, "xcom_pull a tareas inexistentes:\n" + "\n".join(
        f"  {p}" for p in problemas
    )


def _cadenas(valor):
    """Extrae las cadenas de un campo de plantilla, que puede ser str, lista o dict."""
    if isinstance(valor, str):
        yield valor
    elif isinstance(valor, list | tuple):
        for v in valor:
            yield from _cadenas(v)
    elif isinstance(valor, dict):
        for v in valor.values():
            yield from _cadenas(v)


# ── Estructura ────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("dag_id", sorted(DAGS_ESPERADOS))
def test_dag_tiene_tareas_y_dependencias(dagbag, dag_id):
    dag = dagbag.dags[dag_id]
    assert dag.tasks, f"{dag_id} no tiene tareas"

    # Un DAG lineal de N tareas tiene N-1 dependencias. Cero dependencias con
    # varias tareas suele significar que se olvidó el operador >>.
    if len(dag.tasks) > 1:
        aristas = sum(len(t.downstream_task_ids) for t in dag.tasks)
        assert aristas > 0, f"{dag_id} tiene {len(dag.tasks)} tareas sin dependencias"


@pytest.mark.parametrize("dag_id", sorted(DAGS_ESPERADOS))
def test_dag_no_usa_api_de_airflow_2(dagbag, dag_id):
    """`schedule_interval` se eliminó en Airflow 3 en favor de `schedule`."""
    dag = dagbag.dags[dag_id]
    assert (
        not hasattr(dag, "schedule_interval") or dag.schedule is not None
    ), f"{dag_id} no declara schedule"


@pytest.mark.parametrize("dag_id", sorted(DAGS_ESPERADOS))
def test_dag_tiene_timeout(dagbag, dag_id):
    """Sin execution_timeout, una tarea colgada bloquea el slot indefinidamente."""
    dag = dagbag.dags[dag_id]
    sin_timeout = [
        t.task_id
        for t in dag.tasks
        if t.execution_timeout is None and dag.default_args.get("execution_timeout") is None
    ]
    assert not sin_timeout, f"{dag_id}: tareas sin execution_timeout: {sin_timeout}"


# ── Fecha de ejecución ────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "modulo",
    ["dag_indicadores_financieros", "dag_arclim_riesgo_climatico"],
)
def test_fecha_ejecucion_sin_ds(modulos_dag, modulo):
    """`ds` no existe en los runs manuales de Airflow 3.

    Fue un KeyError real en dos DAGs distintos. La función debe caer a
    logical_date y, si tampoco está, a la fecha actual.
    """
    fn = modulos_dag[modulo]._fecha_ejecucion

    assert fn({"ds": "2026-01-15"}) == "2026-01-15"

    from datetime import datetime

    logical = datetime(2026, 3, 4, tzinfo=UTC)
    assert fn({"logical_date": logical}) == "2026-03-04"

    # Contexto vacío: no debe lanzar, debe devolver una fecha ISO.
    resultado = fn({})
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", resultado), resultado


# ── Credenciales ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "modulo",
    ["dag_indicadores_financieros", "dag_arclim_riesgo_climatico"],
)
def test_credenciales_desde_el_entorno(modulos_dag, modulo):
    """Las credenciales no deben tener valores por defecto en el código.

    Un default como 'minioadmin' hace que el DAG se conecte con credenciales
    equivocadas y falle mucho después, con un error de S3 que no señala la
    causa.
    """
    m = modulos_dag[modulo]
    assert m.MINIO_ACCESS == "test-user"
    assert m.MINIO_SECRET == "test-password"  # pragma: allowlist secret
    assert m.MINIO_ENDPOINT == "http://minio-test:9000"
