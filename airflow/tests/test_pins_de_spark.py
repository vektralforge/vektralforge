"""Los pins de Spark tienen que coincidir entre `airflow/` y `spark/`.

`spark/requirements.txt` ya lo dice en su cabecera —«Deben coincidir con
airflow/requirements.txt: el driver corre en el contenedor de Airflow y PySpark
rechaza versiones distintas entre driver y executors»— pero era un comentario,
y un comentario no falla.

El CI tampoco podía notarlo: el job de tests de Spark instala únicamente
`spark/requirements-dev.txt`, así que `spark/requirements.txt` no lo instala
nadie. Y Dependabot abre un PR por archivo. La combinación daba veredictos
opuestos para el mismo cambio: el PR que tocaba `airflow/` fallaba con
`ResolutionImpossible` y el que tocaba `spark/` salía en verde.
"""

from pathlib import Path

import pytest
from packaging.requirements import InvalidRequirement, Requirement
from packaging.utils import canonicalize_name

RAIZ = Path(__file__).resolve().parents[2]

# Los que comparten driver y executors. Si alguno deja de existir, el test lo
# dice en vez de pasar en silencio.
COMPARTIDOS = ("pyspark", "delta-spark")


def _pins(ruta: Path) -> dict[str, str]:
    """Nombre canónico -> especificador, para las líneas que fijan una versión."""
    pins: dict[str, str] = {}
    for cruda in ruta.read_text(encoding="utf-8").splitlines():
        linea = cruda.split("#", 1)[0].strip()
        # Las opciones de pip (-r, --constraint) no son requisitos.
        if not linea or linea.startswith("-"):
            continue
        try:
            req = Requirement(linea)
        except InvalidRequirement:
            pytest.fail(f"{ruta.name}: línea no parseable: {cruda!r}")
        pins[canonicalize_name(req.name)] = str(req.specifier)
    return pins


@pytest.fixture(scope="module")
def pins() -> dict[str, dict[str, str]]:
    return {
        "airflow": _pins(RAIZ / "airflow" / "requirements.txt"),
        "spark": _pins(RAIZ / "spark" / "requirements.txt"),
    }


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_el_paquete_esta_en_ambos_requirements(pins, paquete):
    nombre = canonicalize_name(paquete)
    for lado, contenido in pins.items():
        assert nombre in contenido, f"{paquete} no aparece en {lado}/requirements.txt"


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_los_pins_coinciden_entre_airflow_y_spark(pins, paquete):
    nombre = canonicalize_name(paquete)
    en_airflow = pins["airflow"].get(nombre)
    en_spark = pins["spark"].get(nombre)
    assert en_airflow == en_spark, (
        f"{paquete}: airflow fija '{en_airflow}' y spark fija '{en_spark}'. "
        "El driver corre en el contenedor de Airflow y los executors en el de "
        "Spark; PySpark rechaza versiones distintas entre ambos."
    )


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_el_pin_es_exacto(pins, paquete):
    """Un rango deja que driver y executors se separen sin que nadie avise."""
    nombre = canonicalize_name(paquete)
    for lado, contenido in pins.items():
        spec = contenido.get(nombre, "")
        assert spec.startswith("=="), (
            f"{paquete} en {lado}/requirements.txt está fijado como '{spec}'; "
            "tiene que ser una igualdad exacta."
        )
