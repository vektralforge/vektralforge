#!/bin/bash
# Crea múltiples bases de datos en PostgreSQL al iniciar el contenedor.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE airflow;
    CREATE DATABASE metastore;
EOSQL
