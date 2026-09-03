# Gestión de secretos en vektralforge

> **In English.** Secret handling per environment, and why the project uses
> OpenBao rather than HashiCorp Vault (Vault moved to BSL v1.1 in August 2023;
> OpenBao is the MPL 2.0 fork under the Linux Foundation, API-compatible).
> Locally, secrets are delivered as **files** under `/run/secrets/`, never as
> environment variables — see
> [docs/arquitectura.md](arquitectura.md), section 8, for the full picture.

| Ambiente | Herramienta | Estado |
|---|---|---|
| Local | `.env` → archivos en `/run/secrets/` | Operativo |
| Staging | Sealed Secrets | En evaluación |
| Producción | OpenBao | Planificado |

Las credenciales **no llegan a los contenedores como variables de entorno**.
Compose las entrega como secretos montados en `/run/secrets/<nombre>` y el
entrypoint de cada imagen las materializa en el formato que su consumidor sabe
leer. El detalle está en [`arquitectura.md`](arquitectura.md), sección 8.

## Por qué OpenBao y no HashiCorp Vault

HashiCorp cambió Vault a BSL v1.1 en agosto 2023 (source-available, no open source).
OpenBao es el fork MPL 2.0 bajo Linux Foundation con API 100% compatible.

## Uso con hvac (cliente Python)

```python
import hvac
import os

client = hvac.Client(
    url=os.environ["OPENBAO_ADDR"],
    token=os.environ["OPENBAO_TOKEN"],
)

# Leer secreto
secret = client.secrets.kv.v2.read_secret_version(path="sqlserver/credentials")
username = secret["data"]["data"]["username"]
password = secret["data"]["data"]["password"]
```
