"""
Configuración compartida de los tests de DAGs.

Los DAGs leen las credenciales de MinIO a nivel de módulo y sin valores por
defecto: si falta una variable, el import falla. Es deliberado —evita que un
despliegue arranque con credenciales silenciosamente incorrectas— pero implica
que los tests deben proveerlas.
"""

import os
import sys
from pathlib import Path

import pytest

DAGS_DIR = Path(__file__).parent.parent / "dags"

# Valores de prueba: los tests no se conectan a ningún servicio, solo necesitan
# que las variables existan para que los módulos se importen.
ENTORNO_PRUEBA = {
    "MINIO_ENDPOINT": "http://minio-test:9000",
    "MINIO_ROOT_USER": "test-user",
    "MINIO_ROOT_PASSWORD": "test-password",  # pragma: allowlist secret
    "AIRFLOW__CORE__LOAD_EXAMPLES": "False",
    "AIRFLOW__CORE__UNIT_TEST_MODE": "True",
}


@pytest.fixture(scope="session", autouse=True)
def entorno():
    previo = {k: os.environ.get(k) for k in ENTORNO_PRUEBA}
    os.environ.update(ENTORNO_PRUEBA)
    yield
    for k, v in previo.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


@pytest.fixture(scope="session")
def dagbag(entorno):
    """DagBag cargado desde airflow/dags/.

    En Airflow 3, DagBag ya no acepta include_examples: la carga de ejemplos
    se controla con AIRFLOW__CORE__LOAD_EXAMPLES, que ENTORNO_PRUEBA fija en
    False.
    """
    from airflow.models import DagBag

    return DagBag(dag_folder=str(DAGS_DIR))


@pytest.fixture(scope="session")
def modulos_dag(entorno):
    """Importa cada archivo de dags/ como módulo para poder probar sus funciones."""
    import importlib.util

    if str(DAGS_DIR) not in sys.path:
        sys.path.insert(0, str(DAGS_DIR))

    modulos = {}
    for ruta in sorted(DAGS_DIR.glob("*.py")):
        spec = importlib.util.spec_from_file_location(ruta.stem, ruta)
        modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(modulo)
        modulos[ruta.stem] = modulo
    return modulos
