#!/bin/bash
set -e

# Las bases se leen de POSTGRES_MULTIPLE_DATABASES, que el compose ya pasaba y
# este script ignoraba: la lista estaba escrita a mano aquí y se había quedado
# sin `superset`. No se notó porque init_users.sh tiene una red de seguridad que
# crea las que falten, así que el desfase quedaba tapado.
: "${POSTGRES_MULTIPLE_DATABASES:=airflow,metastore,marquez,superset}"

IFS=',' read -ra bases <<< "$POSTGRES_MULTIPLE_DATABASES"
for base in "${bases[@]}"; do
    base="$(echo "$base" | tr -d '[:space:]')"
    [ -z "$base" ] && continue
    echo "  creando base $base"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE DATABASE "$base";
EOSQL
done
