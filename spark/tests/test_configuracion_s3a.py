"""Los jobs no deben declarar de dónde salen las credenciales de S3A.

Este test existe por un fallo concreto. Las credenciales de MinIO se sacaron
del entorno y pasaron a un `core-site.xml` que el entrypoint escribe al
arrancar el contenedor; ese archivo declara
`fs.s3a.aws.credentials.provider = SimpleAWSCredentialsProvider`, que es el
proveedor que lee la clave de la propia configuración.

Pero los dos jobs fijaban además esa misma propiedad a
`EnvironmentVariableCredentialsProvider` con un `.config(...)`, y la
configuración de la SparkSession gana sobre `core-site.xml`. Resultado: S3A
seguía buscando la clave en un entorno del que ya se había quitado, y el DAG
moría con «Unable to load credentials from system settings» a mitad de la
escritura en Delta.

La propiedad se declara en UN sitio. Los jobs describen QUÉ escriben, no de
dónde salen sus credenciales.

Se leen los archivos como texto y no se importan: importarlos levanta una
SparkSession.
"""

from pathlib import Path

import pytest

JOBS = sorted((Path(__file__).parent.parent / "jobs").glob("bronze_*.py"))

# La clave y el identificador tampoco: irían en la línea de comandos del
# proceso y en la UI del driver.
PROHIBIDAS = (
    "fs.s3a.aws.credentials.provider",
    "fs.s3a.access.key",
    "fs.s3a.secret.key",
)


def test_hay_jobs_que_revisar():
    """Sin esto, un cambio de nombre dejaría el test en verde sin revisar nada."""
    assert JOBS, "no se encontró ningún job bronze_*.py que revisar"


@pytest.mark.parametrize("job", JOBS, ids=lambda p: p.name)
@pytest.mark.parametrize("propiedad", PROHIBIDAS)
def test_job_no_declara_credenciales_de_s3a(job, propiedad):
    lineas = [
        f"  {n}: {linea.strip()}"
        for n, linea in enumerate(job.read_text(encoding="utf-8").splitlines(), 1)
        if propiedad in linea and not linea.lstrip().startswith("#")
    ]
    assert not lineas, (
        f"{job.name} declara {propiedad}, que ya declara core-site.xml:\n" + "\n".join(lineas)
    )
