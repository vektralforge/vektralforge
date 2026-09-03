# infra/k3s/secrets

> **El despliegue a K3s está planificado, no implementado.** Este directorio
> describe cómo se gestionarán los secretos cuando exista; hoy no hay ningún
> manifiesto que los consuma. Ver el issue «Despliegue a K3s».

## Qué hay que trasladar

El stack local entrega sus secretos como **archivos**, no como variables de
entorno: Compose los monta en `/run/secrets/<nombre>` y cada servicio los lee de
ahí. Eso fue el trabajo de los §2.6, §2.9 y §2.10, y traslada bien — un `Secret`
montado como volumen en Kubernetes es exactamente la misma forma, así que los
entrypoints no cambian.

Los cuatro secretos del stack:

| Secreto | Lo consume |
|---|---|
| `postgres_password` | Airflow, metastore, Marquez, Superset |
| `minio_pipeline_secret_key` | Airflow y Spark, cuenta `vf-pipeline` |
| `minio_hive_secret_key` | Metastore, cuenta `vf-hive` |
| `minio_trino_secret_key` | Trino, cuenta `vf-trino` |

Más las contraseñas de administración de Airflow y Superset y las claves de
Airflow (`FERNET_KEY`, `API__SECRET_KEY`, `JWT_SECRET`), que hoy viven en el
`.env` y allí seguirán viniendo de `make init-env`.

## Estrategia por ambiente

- **Staging**: Sealed Secrets — cifrados en Git, descifrables solo por el
  cluster.
- **Producción**: OpenBao, el fork open source de HashiCorp Vault bajo la Linux
  Foundation. Licencia MPL 2.0, API compatible con Vault.

En local OpenBao corre en modo `-dev`: almacenamiento en memoria y sellado
automático. **No es una configuración de producción** y hoy no lo usa nadie.

## Crear un Sealed Secret para staging

```bash
kubectl create secret generic minio-pipeline \
  --from-literal=secret-key="$(grep '^MINIO_PIPELINE_SECRET_KEY=' infra/docker-compose/.env | cut -d= -f2-)" \
  --dry-run=client -o yaml > /tmp/secret.yaml
kubeseal --format yaml < /tmp/secret.yaml > infra/k3s/secrets/minio-pipeline-sealed.yaml
rm /tmp/secret.yaml
git add infra/k3s/secrets/minio-pipeline-sealed.yaml
```

El `rm` no es cosmético: `/tmp/secret.yaml` lleva la clave en claro.

## Leer un secreto de OpenBao

```bash
bao status
bao kv get secret/minio/pipeline
```
