# hive/schemas — Migraciones DDL

Convención Flyway: `V{NNN}__{descripcion}.sql`
Las tablas son escritas por Spark y consultadas por Trino.
Aplicadas por DAG Airflow en cada deploy.
Solo cambios aditivos — nunca modificar migraciones ya aplicadas.
