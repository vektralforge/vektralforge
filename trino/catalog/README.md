# Catálogos de Trino

Cada archivo `.properties` define un conector. Trino los carga al arrancar y
expone cada uno como un catálogo consultable por nombre de archivo: el catálogo
de `delta.properties` se consulta como `delta.esquema.tabla`.

## Catálogos activos

| Archivo | Catálogo | Descripción |
| --- | --- | --- |
| `delta.properties` | `delta` | Tablas Delta Lake sobre MinIO, vía Hive Metastore. Es el catálogo principal del lakehouse. |

## Catálogos de ejemplo (desactivados)

Los archivos con extensión `.disabled` no son cargados por Trino. Sirven como
plantilla para consultas federadas contra fuentes externas.

### `sqlserver.properties.disabled`

Conector a SQL Server para consultar el DWH corporativo sin replicar los datos
al lakehouse. Para activarlo:

1. Renombra el archivo a `sqlserver.properties`.
2. Ajusta `connection-url` con el host, puerto y base de datos reales.
3. Define `SQLSERVER_USER` y `SQLSERVER_PASSWORD` en el entorno del contenedor
   de Trino. La sintaxis `${ENV:VARIABLE}` es interpolación propia de Trino y se
   resuelve en runtime, de modo que las credenciales nunca quedan en el archivo.
4. Reinicia Trino: `make dev-down && make dev-up`.

En despliegues sobre K3s las credenciales se inyectan desde OpenBao. Ver
[`docs/secretos.md`](../../docs/secretos.md).

## Agregar un catálogo nuevo

Crea un archivo `<nombre>.properties` en este directorio con al menos
`connector.name` y los parámetros de conexión del conector. La lista de
conectores disponibles está en la documentación de Trino.

Nunca escribas credenciales literales en estos archivos: usa `${ENV:VARIABLE}` y
declara la variable en el entorno. El hook de `detect-secrets` bloqueará el
commit si detecta un valor que parezca una credencial.
