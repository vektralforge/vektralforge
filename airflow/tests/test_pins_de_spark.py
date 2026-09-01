"""Las versiones de Spark tienen que coincidir en los siete sitios que las fijan.

`spark/requirements.txt` ya lo exigía en su cabecera —«Deben coincidir con
airflow/requirements.txt: el driver corre en el contenedor de Airflow y PySpark
rechaza versiones distintas entre driver y executors»— pero era un comentario, y
un comentario no falla.

Y no son dos sitios, son siete. Al preparar la subida a Spark 4.2 aparecieron:

  airflow/requirements.txt            pyspark, delta-spark
  spark/requirements.txt              pyspark, delta-spark
  airflow/Dockerfile                  pip install pyspark==... delta-spark==...
  airflow/Dockerfile                  ARG DELTA_VERSION
  spark/Dockerfile                    ARG DELTA_VERSION
  spark/Dockerfile                    FROM apache/spark:...
  docker-compose.yml                  image: vektralforge/spark:...

El `pip install` del Dockerfile de Airflow es el peligroso: instala desde
requirements.txt y acto seguido **desinstala pyspark y lo reinstala a mano**.
Subir el requirements sin tocar esa línea no cambia nada dentro de la imagen.

Ninguno de esos sitios lo vigila Dependabot, que solo mira requirements y
etiquetas de `FROM`. Y el CI no construye imágenes, así que un desajuste ahí no
sale en rojo: sale en producción.
"""

import re
from pathlib import Path

import pytest
from packaging.requirements import InvalidRequirement, Requirement
from packaging.utils import canonicalize_name

RAIZ = Path(__file__).resolve().parents[2]

REQ_AIRFLOW = RAIZ / "airflow" / "requirements.txt"
REQ_SPARK = RAIZ / "spark" / "requirements.txt"
DOCKER_AIRFLOW = RAIZ / "infra" / "docker-compose" / "airflow" / "Dockerfile"
DOCKER_SPARK = RAIZ / "infra" / "docker-compose" / "spark" / "Dockerfile"
COMPOSE = RAIZ / "infra" / "docker-compose" / "docker-compose.yml"

COMPARTIDOS = ("pyspark", "delta-spark")


def _pins_requirements(ruta: Path) -> dict[str, str]:
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


def _uno(patron: str, ruta: Path, que: str) -> str:
    """Primera captura de `patron` en `ruta`, exigiendo que aparezca una sola vez."""
    hallazgos = re.findall(patron, ruta.read_text(encoding="utf-8"), re.MULTILINE)
    assert hallazgos, f"no se encontró {que} en {ruta.relative_to(RAIZ)}"
    assert len(set(hallazgos)) == 1, (
        f"{que} aparece con valores distintos en {ruta.relative_to(RAIZ)}: {set(hallazgos)}"
    )
    return hallazgos[0]


@pytest.fixture(scope="module")
def requirements() -> dict[str, dict[str, str]]:
    return {
        "airflow/requirements.txt": _pins_requirements(REQ_AIRFLOW),
        "spark/requirements.txt": _pins_requirements(REQ_SPARK),
    }


@pytest.fixture(scope="module")
def pip_del_dockerfile() -> dict[str, str]:
    """El `pip install pyspark==X delta-spark==Y` escrito a mano en la imagen."""
    return {
        "pyspark": _uno(
            r"pip install [^\n]*?pyspark==([\d.]+)", DOCKER_AIRFLOW, "el pin de pyspark"
        ),
        "delta-spark": _uno(
            r"pip install [^\n]*?delta-spark==([\d.]+)", DOCKER_AIRFLOW, "el pin de delta-spark"
        ),
    }


# ── Los pines de Python ──────────────────────────────────────────────────────


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_el_paquete_esta_en_ambos_requirements(requirements, paquete):
    nombre = canonicalize_name(paquete)
    for archivo, contenido in requirements.items():
        assert nombre in contenido, f"{paquete} no aparece en {archivo}"


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_los_requirements_coinciden_entre_si(requirements, paquete):
    nombre = canonicalize_name(paquete)
    en_airflow = requirements["airflow/requirements.txt"].get(nombre)
    en_spark = requirements["spark/requirements.txt"].get(nombre)
    assert en_airflow == en_spark, (
        f"{paquete}: airflow fija '{en_airflow}' y spark fija '{en_spark}'. "
        "El driver corre en el contenedor de Airflow y los executors en el de "
        "Spark; PySpark rechaza versiones distintas entre ambos."
    )


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_el_pin_es_exacto(requirements, paquete):
    """Un rango deja que driver y executors se separen sin que nadie avise."""
    nombre = canonicalize_name(paquete)
    for archivo, contenido in requirements.items():
        spec = contenido.get(nombre, "")
        assert spec.startswith("=="), (
            f"{paquete} en {archivo} está fijado como '{spec}'; tiene que ser una igualdad exacta."
        )


@pytest.mark.parametrize("paquete", COMPARTIDOS)
def test_el_pip_del_dockerfile_no_contradice_al_requirements(
    requirements, pip_del_dockerfile, paquete
):
    """El Dockerfile de Airflow reinstala estos paquetes a mano después de pip.

    Si esa línea se queda atrás, la imagen ignora el requirements en silencio.
    """
    esperado = requirements["airflow/requirements.txt"][canonicalize_name(paquete)]
    assert f"=={pip_del_dockerfile[paquete]}" == esperado, (
        f"{paquete}: airflow/requirements.txt dice '{esperado}' pero el "
        f"Dockerfile reinstala '=={pip_del_dockerfile[paquete]}'. Gana el "
        "Dockerfile, y nadie se entera."
    )


# ── Los pines de los Dockerfiles y del Compose ───────────────────────────────


def test_delta_coincide_con_el_arg_de_los_dockerfiles(requirements):
    """El ARG resuelve el JAR de Delta con Maven; el requirements, el paquete."""
    esperado = requirements["spark/requirements.txt"][canonicalize_name("delta-spark")]
    for ruta in (DOCKER_SPARK, DOCKER_AIRFLOW):
        arg = _uno(r"^ARG DELTA_VERSION=([\d.]+)", ruta, "ARG DELTA_VERSION")
        assert f"=={arg}" == esperado, (
            f"{ruta.relative_to(RAIZ)}: ARG DELTA_VERSION={arg} contra "
            f"delta-spark{esperado} en los requirements. El JAR y el paquete "
            "de Python tienen que ser la misma versión."
        )


def test_pyspark_coincide_con_la_imagen_de_spark(requirements):
    """`FROM apache/spark:X` fija los JAR del cluster; pyspark, los del driver."""
    imagen = _uno(r"^FROM apache/spark:([\d.]+)", DOCKER_SPARK, "FROM apache/spark")
    esperado = requirements["spark/requirements.txt"][canonicalize_name("pyspark")]
    assert f"=={imagen}" == esperado, (
        f"la imagen es apache/spark:{imagen} y pyspark{esperado}. "
        "Un cliente y un cluster desalineados fallan con errores de protocolo "
        "poco descriptivos."
    )


def test_la_etiqueta_del_compose_sigue_a_la_version_de_spark(requirements):
    """`vektralforge/spark:X` es lo que se reconstruye; si miente, confunde."""
    etiqueta = _uno(r"image: vektralforge/spark:([\d.]+)", COMPOSE, "la etiqueta de la imagen")
    esperado = requirements["spark/requirements.txt"][canonicalize_name("pyspark")]
    assert f"=={etiqueta}" == esperado, (
        f"el compose etiqueta vektralforge/spark:{etiqueta} y pyspark{esperado}."
    )


# ── Los ARG que los dos Dockerfiles comparten ────────────────────────────────


@pytest.mark.parametrize(
    "arg", ("HADOOP_VERSION", "SCALA_BINARY", "OPENLINEAGE_VERSION", "SPARK_MINOR")
)
def test_los_dockerfiles_comparten_los_mismos_args(arg):
    """Los dos resuelven los MISMOS JAR: el driver corre en el de Airflow.

    HADOOP_VERSION es el más silencioso de los tres. Debe corresponder al Hadoop
    que trae la imagen de Spark —4.0.0 traía 3.4.1 y 4.2.0 trae 3.5.0—, y
    Dependabot no lo mira: no es un `FROM` ni un requirement.
    """
    valores = {
        ruta.parent.name: _uno(rf"^ARG {arg}=([\w.\-]+)", ruta, f"ARG {arg}")
        for ruta in (DOCKER_SPARK, DOCKER_AIRFLOW)
    }
    assert len(set(valores.values())) == 1, f"ARG {arg} difiere entre los Dockerfiles: {valores}"


def test_spark_minor_corresponde_a_la_version_de_pyspark(requirements):
    """`SPARK_MINOR` elige el artefacto de Delta compilado para ese Spark.

    Desde Delta 4.1 el artefacto lleva la versión de Spark en el nombre
    (delta-spark_4.0, _4.1, _4.2). Apuntar al de otra menor compila y arranca,
    y falla luego con errores de método no encontrado.
    """
    menor = _uno(r"^ARG SPARK_MINOR=([\d.]+)", DOCKER_SPARK, "ARG SPARK_MINOR")
    pyspark = requirements["spark/requirements.txt"][canonicalize_name("pyspark")].lstrip("=")
    assert pyspark.startswith(f"{menor}."), (
        f"ARG SPARK_MINOR={menor} contra pyspark=={pyspark}. El artefacto de "
        "Delta tiene que ser el compilado para esa versión menor de Spark."
    )
