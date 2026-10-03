#!/usr/bin/env bash
# .ci/scripts/verificar_permisos.sh
#
# Comprueba que la cuenta de servicio del pipeline esté ACOTADA: que pueda
# operar sobre los objetos de los cinco buckets y que no pueda nada más.
#
# Por qué existe. El §2.9 dejó a cada consumidor con una cuenta limitada por
# politica-datos.json en vez de la raíz, y hasta ahora eso se comprobaba a mano
# una vez y se daba por bueno. Un permiso de más no da ningún síntoma: el stack
# funciona igual de bien con una cuenta acotada que con una que pueda borrar
# todos los buckets. Lo único que distingue un caso del otro es intentarlo.
#
# EL ORDEN NO ES CASUAL. Los controles POSITIVOS van delante de los negativos,
# que es la lección del #53: un conjunto de comprobaciones «esto debe fallar»
# da verde también cuando lo que está roto es la prueba —credencial mal leída,
# endpoint equivocado, cliente que no llega—. Si los positivos pasan, sabemos
# que el método funciona y que un negativo que falla lo hace por la política.
#
# UN NoSuchBucket NO ES UN APROBADO. En los controles negativos solo cuenta
# AccessDenied: si el servidor responde «ese bucket no existe» es que la
# petición pasó la autorización y llegó a buscarlo, que es justo lo que no debe
# ocurrir. El guion lo trata como fallo y dice por qué.
#
# De dónde salen las credenciales: de ningún sitio. El guion corre DENTRO del
# contenedor de Airflow y usa el perfil que su entrypoint ya materializó para
# boto3 (#55), así que aquí no se lee, ni se pasa, ni se imprime ningún secreto.
#
# Alcance: se prueba vf-pipeline. Las tres cuentas comparten
# politica-datos.json, de modo que lo que se verifica es que ESA política se
# aplica. Que vf-hive y vf-trino estén atadas a ella lo demuestra el pipeline:
# si no lo estuvieran, el metastore no habría creado sus prefijos ni Trino
# podría leer, y `make dev-load-example` no terminaría.

set -uo pipefail

C_AIRFLOW=docker-compose-airflow-webserver-1
CUENTA_ESPERADA="${1:-vf-pipeline}"

if ! docker inspect --format='{{.State.Status}}' "$C_AIRFLOW" 2>/dev/null | grep -q running; then
    echo "  ✗ $C_AIRFLOW no está corriendo. Ejecuta: make dev-up" >&2
    exit 1
fi

docker exec -i -e CUENTA_ESPERADA="$CUENTA_ESPERADA" "$C_AIRFLOW" python3 - \
    < .ci/scripts/verificar_permisos.py
