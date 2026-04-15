# Gestión de secretos

| Ambiente | Herramienta     | Notas                                   |
|----------|-----------------|-----------------------------------------|
| Local    | `.env` file     | Nunca commitear                         |
| Staging  | Sealed Secrets  | Cifrado en Git, descifrado por K3s      |
| Prod     | HashiCorp Vault | Rotación automática + auditoría         |

## Variables requeridas

- `SQLSERVER_USER` / `SQLSERVER_PASSWORD`
- `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`
- `AIRFLOW__CORE__FERNET_KEY`
- `AIRFLOW__WEBSERVER__SECRET_KEY`
