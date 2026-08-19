# Gestión de secretos en vektralforge

| Ambiente | Herramienta | Estado |
|---|---|---|
| Local | `.env` | Operativo |
| Staging | Sealed Secrets | En evaluación |
| Producción | OpenBao | Planificado |

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
