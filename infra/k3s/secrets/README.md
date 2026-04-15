# infra/k3s/secrets

Este directorio contiene los Sealed Secrets cifrados para staging.

## Cómo crear un Sealed Secret

```bash
# 1. Crear el secret normal de K8s (NO commitear este archivo)
kubectl create secret generic sqlserver-credentials \
  --from-literal=username=sa \
  --from-literal=password=my-password \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. Cifrar con kubeseal
kubeseal --format yaml < /tmp/secret.yaml > infra/k3s/secrets/sqlserver-credentials-sealed.yaml

# 3. Eliminar el archivo temporal
rm /tmp/secret.yaml

# 4. Commitear el archivo .sealed.yaml (es seguro)
git add infra/k3s/secrets/sqlserver-credentials-sealed.yaml
```

## En producción

Los secretos de producción se gestionan en **HashiCorp Vault**, no en este directorio.
Ver documentación en docs/secretos.md
