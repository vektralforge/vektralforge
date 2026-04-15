# infra/k3s/secrets

Gestión de secretos por ambiente:
  - Staging:    Sealed Secrets (cifrado en Git)
  - Producción: OpenBao (MPL 2.0 / Linux Foundation / API Vault-compatible)

## Crear Sealed Secret para staging

```bash
kubectl create secret generic sqlserver-credentials \
  --from-literal=username=sa --from-literal=password=my-password \
  --dry-run=client -o yaml > /tmp/secret.yaml
kubeseal --format yaml < /tmp/secret.yaml > infra/k3s/secrets/sqlserver-credentials-sealed.yaml
rm /tmp/secret.yaml
git add infra/k3s/secrets/sqlserver-credentials-sealed.yaml
```

## OpenBao en producción

OpenBao es el fork open source de HashiCorp Vault bajo la Linux Foundation.
Licencia MPL 2.0 — sin restricciones BSL. API 100% compatible con Vault.

```bash
# Verificar estado
bao status

# Leer secreto
bao kv get secret/sqlserver/credentials
```
