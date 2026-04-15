-- ─────────────────────────────────────────────────────────────────────────────
-- V001__create_bronze_example.sql
-- Migración inicial: crea tabla bronze de ejemplo en Hive Metastore.
-- Aplicada por: DAG airflow de migración en cada deploy.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS bronze;

CREATE EXTERNAL TABLE IF NOT EXISTS bronze.example (
    id          BIGINT      COMMENT 'Identificador único',
    nombre      STRING      COMMENT 'Nombre del registro',
    activo      BOOLEAN     COMMENT 'Estado activo/inactivo',
    fecha_carga TIMESTAMP   COMMENT 'Timestamp de carga'
)
STORED AS PARQUET
LOCATION 's3a://bronze/example/'
TBLPROPERTIES (
    'delta.minReaderVersion' = '1',
    'delta.minWriterVersion' = '2'
);
