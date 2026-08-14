# Autenticación de Airflow con FAB auth manager

Guía para cambiar VektralForge de **SimpleAuthManager** (el predeterminado de
Airflow 3) a **FabAuthManager**, que aporta gestión de usuarios y roles desde la
interfaz y desde la CLI.

## Por qué

Airflow 3 empaqueta autenticación y autorización en un componente llamado *auth
manager*, y trae SimpleAuthManager por defecto. Ese componente está pensado para
entornos de un solo usuario: los usuarios se declaran en configuración y las
contraseñas se autogeneran, sin interfaz de administración.

| | SimpleAuthManager | FabAuthManager |
| --- | --- | --- |
| Usuarios | Declarados en configuración | En base de datos |
| Contraseñas | Autogeneradas | Definidas por quien administra |
| Roles | Fijos (admin, op, user, viewer, public) | Personalizables, permisos por DAG |
| Gestión desde la UI | No | Sí |
| `airflow users` en CLI | No disponible | Disponible |
| SSO / OAuth / LDAP | No | Sí |

Para VektralForge, que otros equipos van a desplegar y donde varias personas
comparten el entorno, FAB es la opción adecuada. SimpleAuthManager sirve para
desarrollo individual.

FAB añade unas quince tablas a la base de metadatos y algo de latencia por la
comprobación de permisos. Es el costo de tener control de acceso real.

---

## 1. Instalar el proveedor

En `airflow/requirements.txt`:

```
apache-airflow==3.3.0
apache-airflow-providers-fab==3.7.1
```

Verifica la versión compatible con tu Airflow antes de fijarla — el proveedor
tiene su propio ciclo de publicación:

```bash
pip index versions apache-airflow-providers-fab
```

Fíjala con `==` en lugar de `>=`: FAB toca autenticación, y una actualización
automática no es algo que quieras descubrir en un despliegue.

## 2. Configurar el auth manager

En `infra/docker-compose/docker-compose.yml`, dentro de `x-airflow-common`:

```yaml
x-airflow-common: &airflow-common
  build: ./airflow
  env_file: .env
  environment:
    AIRFLOW__CORE__AUTH_MANAGER: airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/airflow
    # ... el resto sin cambios
```

Añádelo también a `airflow-init`, que no usa el ancla `*airflow-common` y
necesita la misma configuración para migrar las tablas de FAB.

Si tenías variables de SimpleAuthManager (`AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_*`),
elimínalas: dejarlas confunde a quien lea el archivo después.

## 3. Migrar la base de datos

FAB mantiene sus tablas en migraciones **separadas** de las de Airflow. `airflow
db migrate` no las crea; hace falta un comando propio:

```yaml
  airflow-init:
    build: ./airflow
    env_file: .env
    environment:
      AIRFLOW__CORE__AUTH_MANAGER: airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/airflow
    command: >
      bash -c "airflow db migrate && airflow fab-db migrate"
    restart: "no"
```

Olvidar `fab-db migrate` es el error más común de esta migración: Airflow arranca
sin quejarse y falla al primer intento de login, con un error de tabla
inexistente que no dice nada obvio.

## 4. Reconstruir y levantar

```bash
make dev-down
docker compose --env-file infra/docker-compose/.env \
  -f infra/docker-compose/docker-compose.yml build airflow-webserver
make dev-reset
```

`dev-reset` en vez de `dev-up` porque las tablas de FAB se crean en la migración
inicial.

## 5. Crear el usuario administrador

Con FAB activo, el comando vuelve a existir y `.ci/scripts/init_users.sh` lo
detecta solo. Manualmente sería:

```bash
docker exec docker-compose-airflow-webserver-1 \
  airflow users create \
    --username admin \
    --password "$(grep '^AIRFLOW_ADMIN_PASSWORD=' infra/docker-compose/.env | cut -d= -f2-)" \
    --firstname Admin \
    --lastname VektralForge \
    --role Admin \
    --email admin@example.com
```

## 6. Verificar

```bash
# Auth manager activo
docker exec docker-compose-airflow-webserver-1 \
  airflow config get-value core auth_manager

# Usuarios existentes
docker exec docker-compose-airflow-webserver-1 airflow users list

# Roles disponibles
docker exec docker-compose-airflow-webserver-1 airflow roles list
```

El primer comando debe devolver la ruta completa de `FabAuthManager`. Después,
entra a `http://localhost:8090` con las credenciales del `.env`.

---

## Roles predefinidos

| Rol | Permisos |
| --- | --- |
| `Public` | Ninguno |
| `Viewer` | Lectura de DAGs, tareas y logs |
| `User` | Viewer + ejecutar, pausar y limpiar DAGs |
| `Op` | User + conexiones, variables, pools y configuración |
| `Admin` | Todo, incluida la gestión de usuarios |

Para un equipo de datos, la asignación habitual es `Admin` para quien opera la
plataforma, `Op` para ingeniería de datos y `Viewer` para analistas.

Se pueden crear roles con acceso limitado a DAGs concretos, lo que resulta útil
cuando varios equipos comparten una instancia:

```bash
docker exec docker-compose-airflow-webserver-1 \
  airflow roles create EquipoClima

docker exec docker-compose-airflow-webserver-1 \
  airflow roles add-perms EquipoClima \
    -a can_read -r DAG:arclim_riesgo_climatico_chile
```

---

## webserver_config.py

FAB lee configuración adicional desde `$AIRFLOW_HOME/webserver_config.py`. Para
autenticación contra la base de datos —el caso por defecto— no hace falta
crearlo. Se vuelve necesario al integrar SSO, LDAP u OAuth.

Si lo necesitas, la plantilla oficial está en el código fuente de Airflow, en
`airflow-core/src/airflow/config_templates/default_webserver_config.py`. Cópiala
a `$AIRFLOW_HOME/webserver_config.py` y ajústala.

Un detalle que causa confusión: para activar OAuth hay que poner
`AUTH_TYPE = AUTH_OAUTH` explícitamente. Configurar `OAUTH_PROVIDERS` sin eso no
tiene efecto, porque el valor por defecto es `AUTH_DB`.

Si añades el archivo, móntalo como volumen para no reconstruir la imagen en cada
cambio:

```yaml
  volumes:
    - ../../airflow/webserver_config.py:/opt/airflow/webserver_config.py
```

Y ojo con el `.gitignore`: la línea `airflow/webserver_config.py` está pensada
para el archivo autogenerado. Si versionas el tuyo, añade una excepción.

---

## API y tokens

En Airflow 3, la API pública usa autenticación por token y ese mecanismo es
independiente del `auth_backend` configurado. Los clientes primero obtienen un
JWT y luego lo envían en cada petición.

```bash
TOKEN=$(curl -s -X POST http://localhost:8090/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"..."}' | jq -r .access_token)

curl -s http://localhost:8090/api/v2/dags -H "Authorization: Bearer $TOKEN"
```

Verifica la ruta exacta del endpoint contra la documentación de tu versión: la
API cambió de forma sustancial en Airflow 3.

---

## Problemas frecuentes

**`relation "ab_user" does not exist`** — falta `airflow fab-db migrate`. Es el
síntoma clásico del paso 3 omitido.

**`airflow users` sigue sin existir** — el proveedor no quedó instalado, o el
contenedor no se reconstruyó. Comprueba con
`docker exec ... pip show apache-airflow-providers-fab`.

**El login devuelve 500** — revisa que `AIRFLOW__CORE__AUTH_MANAGER` esté
definido en *todos* los servicios de Airflow, incluido `airflow-init`. Una
configuración parcial produce estados inconsistentes.

**Conflictos de dependencias al instalar** — FAB fija versiones concretas de
Flask y Flask-AppBuilder. Si choca con algo, revisa qué otra dependencia impone
la restricción antes de forzar versiones.

**Volver atrás:** quita `AIRFLOW__CORE__AUTH_MANAGER` y el stack regresa a
SimpleAuthManager. Las tablas de FAB quedan en la base sin usarse; no estorban.

---

## Antes de desplegar fuera de desarrollo

- Contraseñas reales en el `.env`, no los valores de ejemplo
- `AIRFLOW__API__SECRET_KEY` y `AIRFLOW__CORE__FERNET_KEY` generadas por entorno
- TLS delante del servidor de la API: el login envía credenciales en el cuerpo
  de la petición
- Un rol distinto de `Admin` para el uso cotidiano
- Rotación de credenciales documentada en tu procedimiento operativo

Las guías de despliegue de VektralForge no son asesoría de seguridad. Revisa la
configuración con quien corresponda antes de exponer el servicio.

## Referencias

- Auth manager en Airflow: https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/auth-manager/index.html
- Proveedor FAB: https://airflow.apache.org/docs/apache-airflow-providers-fab/stable/auth-manager/index.html
- Configuración del proveedor: https://airflow.apache.org/docs/apache-airflow-providers-fab/stable/configurations-ref.html
