-- ─────────────────────────────────────────────────────────────────────────────
-- V002__create_silver_example.sql
-- Crea tabla silver de ejemplo (datos limpios y deduplicados).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS silver;

CREATE EXTERNAL TABLE IF NOT EXISTS silver.example (
    id             BIGINT      COMMENT 'Identificador único',
    nombre         STRING      COMMENT 'Nombre del registro',
    activo         BOOLEAN     COMMENT 'Estado activo/inactivo',
    fecha_carga    TIMESTAMP   COMMENT 'Timestamp de carga original',
    fecha_proceso  TIMESTAMP   COMMENT 'Timestamp de procesamiento silver'
)
STORED AS PARQUET
LOCATION 's3a://silver/example/'
TBLPROPERTIES (
    'delta.minReaderVersion' = '1',
    'delta.minWriterVersion' = '2'
);
