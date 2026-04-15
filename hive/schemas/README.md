# hive/schemas — Migraciones DDL

Las migraciones siguen el patrón **Flyway** con numeración secuencial.

## Convención de nombres

```
V{NNN}__{descripcion_corta}.sql
```

Ejemplos:
- `V001__create_bronze_example.sql`
- `V002__create_silver_example.sql`
- `V003__add_column_bronze_example.sql`

## Reglas

- **Solo cambios aditivos** en tablas existentes (nuevas columnas, nuevas tablas).
- Cambios **breaking** (renombrar columnas, cambiar tipos) requieren nueva tabla + migración de datos.
- Las migraciones son **aplicadas automáticamente** por el DAG `airflow/dags/run_hive_migrations.py` en cada deploy.
- **Nunca modificar** una migración ya aplicada. Crear una nueva.
