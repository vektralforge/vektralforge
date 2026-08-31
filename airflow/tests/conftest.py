"""
Configuración compartida de los tests de DAGs.

Los DAGs comprueban a nivel de módulo que el endpoint y las credenciales estén
en el entorno, sin valores por defecto: si falta una variable, el import falla.
Es deliberado —evita que un despliegue arranque con credenciales silenciosamente
incorrectas— pero implica que los tests deben proveerlas.

Las credenciales van en AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY porque es de
ahí de donde las leen boto3 y el EnvironmentVariableCredentialsProvider de S3A.
"""

import os
import sys
from pathlib import Path

import pytest

DAGS_DIR = Path(__file__).parent.parent / "dags"
PLUGINS_DIR = Path(__file__).parent.parent / "plugins"

# Airflow 3 añade la carpeta de plugins al sys.path, pero NO la de DAGs. Se
# replica aquí y no en una fixture porque los tests del código compartido lo
# importan en tiempo de colección. Añadir dags/ haría pasar tests con imports
# que en el contenedor fallan — pasó con http_publico.
if str(PLUGINS_DIR) not in sys.path:
    sys.path.insert(0, str(PLUGINS_DIR))

# Valores de prueba: los tests no se conectan a ningún servicio, solo necesitan
# que las variables existan para que los módulos se importen.
ENTORNO_PRUEBA = {
    "MINIO_ENDPOINT": "http://minio-test:9000",
    "AWS_ACCESS_KEY_ID": "test-user",
    "AWS_SECRET_ACCESS_KEY": "test-password",  # pragma: allowlist secret
    "AIRFLOW__CORE__LOAD_EXAMPLES": "False",
    "AIRFLOW__CORE__UNIT_TEST_MODE": "True",
    # Airflow resuelve el código compartido desde aquí; los tests tienen que
    # apuntar al mismo sitio o dejan de parecerse a producción.
    "AIRFLOW__CORE__PLUGINS_FOLDER": str(PLUGINS_DIR),
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

    modulos = {}
    for ruta in sorted(DAGS_DIR.glob("*.py")):
        spec = importlib.util.spec_from_file_location(ruta.stem, ruta)
        modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(modulo)
        modulos[ruta.stem] = modulo
    return modulos
