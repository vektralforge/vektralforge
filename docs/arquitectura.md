# Arquitectura lakeforge

Ver documento completo: `lakeforge_arquitectura_v3.docx`

## Stack resumido

| Capa            | Herramientas                              |
|-----------------|-------------------------------------------|
| Ingesta         | Apache Kafka, Apache Airflow              |
| Almacenamiento  | MinIO, Delta Lake, Hive Metastore         |
| Procesamiento   | Apache Spark, Trino                       |
| Consumo         | Power BI, Apache Superset, Redis          |
| Seguridad       | HashiCorp Vault, Sealed Secrets           |
| Gobernanza      | Apache Atlas, Apache Ranger, Great Expectations |
| Observabilidad  | Graylog, Prometheus + Grafana (roadmap)   |
| Infraestructura | Docker Compose (local), K3s (prod)        |
