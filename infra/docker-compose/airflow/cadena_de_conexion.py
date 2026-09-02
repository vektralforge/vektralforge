#!/usr/bin/env python3
"""Imprime la cadena de conexión de Airflow a Postgres.

Airflow acepta `AIRFLOW__{SECCION}__{CLAVE}_CMD`: en vez de leer el valor del
entorno, ejecuta un comando y usa su salida. Eso permite que la contraseña
llegue como archivo —el secreto que monta docker-compose— y no como variable,
donde la vería `docker inspect` y cualquier proceso en /proc/<pid>/environ.

Es un script y no un one-liner dentro del YAML por dos motivos: la contraseña
hay que pasarla por quote() para que un '@' o un '/' no parta el netloc de la
URL, y así esto se puede probar sin levantar el stack.
"""

import os
import pathlib
import sys
from urllib.parse import quote


def main() -> int:
    ruta = os.environ.get("POSTGRES_PASSWORD_FILE", "/run/secrets/postgres_password")
    try:
        clave = pathlib.Path(ruta).read_text(encoding="utf-8").strip("\n")
    except OSError as e:
        print(
            f"ERROR: no se puede leer el secreto en {ruta}: {e}\n"
            "       Lo monta docker-compose.yml desde el bloque secrets:;\n"
            "       requiere Compose 2.20 o superior para el origen environment:.",
            file=sys.stderr,
        )
        return 1

    usuario = os.environ.get("POSTGRES_USER", "vektralforge")
    host = os.environ.get("POSTGRES_HOST", "postgres")
    puerto = os.environ.get("POSTGRES_PORT", "5432")
    base = os.environ.get("AIRFLOW_DB_NAME", "airflow")

    # SIN salto de línea final. Airflow no lo recorta: lo arrastra hasta la
    # cadena de conexión, y Postgres acaba buscando una base llamada "airflow\n"
    # —el error dice literalmente `database "airflow⏎" does not exist`—. Por eso
    # write() y no print().
    sys.stdout.write(
        "postgresql+psycopg2://"
        f"{quote(usuario, safe='')}:{quote(clave, safe='')}"
        f"@{host}:{puerto}/{base}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
