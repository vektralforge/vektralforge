"""
Configuración compartida de los tests de DAGs.

Los DAGs comprueban a nivel de módulo que el endpoint esté en el entorno y que
exista el archivo de credenciales, sin valores por defecto: si falta algo, el
import falla. Es deliberado —evita que un despliegue arranque con credenciales
silenciosamente incorrectas— pero implica que los tests deben proveerlo.

Las credenciales ya no viajan en AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY. En
el contenedor las escribe credenciales_minio.sh en un INI del SDK que boto3
encuentra por AWS_SHARED_CREDENTIALS_FILE; aquí se genera uno equivalente en un
temporal para que los tests se parezcan a lo que hay en ejecución.
"""

import os
import sys
import tempfile
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

# Un INI igual al que el entrypoint escribe en el contenedor. Se crea al
# importar este archivo y no dentro de una fixture porque los módulos de DAG
# comprueban su existencia en tiempo de import, que es cuando pytest los
# recoge.
ARCHIVO_CREDENCIALES = Path(tempfile.mkdtemp(prefix="vf-credenciales-")) / "credentials"
ARCHIVO_CREDENCIALES.write_text(
    "[default]\n"
    "aws_access_key_id = test-user\n"
    "aws_secret_access_key = test-password\n",  # pragma: allowlist secret
    encoding="utf-8",
)

# Valores de prueba: los tests no se conectan a ningún servicio, solo necesitan
# que las variables existan para que los módulos se importen.
ENTORNO_PRUEBA = {
    "MINIO_ENDPOINT": "http://minio-test:9000",
    "AWS_SHARED_CREDENTIALS_FILE": str(ARCHIVO_CREDENCIALES),
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
