# Arquitectura lakeforge v2.0

Ver documento completo: `lakeforge_arquitectura_v4.docx`

## Cambios v2.0
- HashiCorp Vault → **OpenBao** (MPL 2.0 / Linux Foundation / API compatible)
- Rol de Spark clarificado: escritura ACID Delta Lake + ELT batch + Streaming Kafka

## Stack

| Capa | Herramientas |
|---|---|
| Ingesta | Apache Kafka, Apache Airflow |
| Almacenamiento | MinIO, Delta Lake, Hive Metastore |
| Procesamiento | Apache Spark (escribe ACID), Trino (lee SQL) |
| Consumo | Power BI, Apache Superset, Redis |
| Seguridad | **OpenBao** (prod), Sealed Secrets (staging) |
| Gobernanza | Apache Atlas, Apache Ranger, Great Expectations |
| Observabilidad | Graylog + Prometheus/Grafana (roadmap) |
| Infraestructura | Docker Compose (local), K3s (prod) |

## Spark vs Trino — separación de responsabilidades

| Operación | Motor |
|---|---|
| Escribir Delta Lake (ACID) | **Spark** |
| MERGE / UPSERT | **Spark** |
| Streaming Kafka → Delta | **Spark Structured Streaming** |
| Consultas SQL ad-hoc | **Trino** |
| Consultas federadas | **Trino** |
