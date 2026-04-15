-- V002: tabla silver/example (datos limpios post-MERGE Spark)
CREATE DATABASE IF NOT EXISTS silver;
CREATE EXTERNAL TABLE IF NOT EXISTS silver.example (
    id             BIGINT    COMMENT 'Identificador único',
    nombre         STRING    COMMENT 'Nombre',
    activo         BOOLEAN   COMMENT 'Estado',
    fecha_carga    TIMESTAMP COMMENT 'Timestamp original',
    fecha_proceso  TIMESTAMP COMMENT 'Timestamp procesamiento silver'
)
STORED AS PARQUET
LOCATION 's3a://silver/example/'
TBLPROPERTIES ('delta.minReaderVersion'='1','delta.minWriterVersion'='2');
