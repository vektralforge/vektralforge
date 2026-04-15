-- V001: tabla bronze/example
-- Escrita por Spark (ACID). Consultada por Trino (SQL).
CREATE DATABASE IF NOT EXISTS bronze;
CREATE EXTERNAL TABLE IF NOT EXISTS bronze.example (
    id          BIGINT    COMMENT 'Identificador único',
    nombre      STRING    COMMENT 'Nombre del registro',
    activo      BOOLEAN   COMMENT 'Estado activo/inactivo',
    fecha_carga TIMESTAMP COMMENT 'Timestamp de carga'
)
STORED AS PARQUET
LOCATION 's3a://bronze/example/'
TBLPROPERTIES ('delta.minReaderVersion'='1','delta.minWriterVersion'='2');
