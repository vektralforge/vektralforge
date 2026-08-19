#!/usr/bin/env bash
#
# Lint de archivos SQL con sqlfluff.
#
# El proyecto no tiene SQL versionado ahora mismo: las tablas Delta las crea
# Spark al escribir con .format("delta"), y load_example.sh las expone en Trino
# con CALL delta.system.register_table. Este paso se mantiene para cuando
# aparezcan vistas o DDL que Delta no gestione.
#
# CUIDADO CON EL DIALECTO: sqlfluff toma el dialecto del archivo .sqlfluff más
# cercano hacia arriba desde cada SQL. Hoy solo existe trino/.sqlfluff. Si se
# añade SQL de Hive —CREATE DATABASE, CREATE EXTERNAL TABLE— hay que crear
# hive/.sqlfluff con `dialect = hive`, o sqlfluff lo validará contra la
# gramática de Trino y fallará con "Found unparsable section".

set -euo pipefail
cd "$(dirname "$0")/../.."

archivos=$(find . -name "*.sql" \
    -not -path "./.git/*" \
    -not -path "./.venv/*" \
    -not -path "*/node_modules/*")

if [ -z "$archivos" ]; then
    echo "  · Sin archivos SQL que revisar"
    exit 0
fi

# shellcheck disable=SC2086  # se quiere la división en palabras
sqlfluff lint $archivos
echo "✓ Lint SQL OK"
