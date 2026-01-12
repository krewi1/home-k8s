# PostgreSQL

PostgreSQL database using Bitnami Helm chart, configured for a home Kubernetes cluster.

## Architecture

- **Single instance** (standalone mode)
- **10Gi persistent storage** using K3s local-path provisioner
- **Resource-optimized** for Raspberry Pi

## Installation

```bash
./install.sh
```

## Uninstallation

```bash
./uninstall.sh
```

## Connection Details

| Property | Value |
|----------|-------|
| Host (in-cluster) | `postgresql.postgres.svc.cluster.local` |
| Port | `5432` |
| Database | `default` |
| Superuser | `postgres` |
| App User | `appuser` |

## Usage

### Connect from within the cluster

```bash
# Run a temporary postgres client pod
kubectl run postgres-client --rm -it --restart=Never \
  --namespace postgres \
  --image bitnami/postgresql:latest \
  --env="PGPASSWORD=$(kubectl get secret -n postgres postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)" \
  -- psql -h postgresql -U postgres -d default
```

### Port-forward for local access

```bash
kubectl port-forward -n postgres svc/postgresql 5432:5432

# Then connect with psql
psql -h localhost -U postgres -d default
```

### Connection string for applications

```
postgresql://appuser:<password>@postgresql.postgres.svc.cluster.local:5432/default
```

### Get passwords

```bash
# Superuser password
kubectl get secret -n postgres postgresql -o jsonpath='{.data.postgres-password}' | base64 -d

# App user password
kubectl get secret -n postgres postgresql -o jsonpath='{.data.password}' | base64 -d
```

## Configuration

Edit `values.yaml` to customize:

- **Passwords**: Change `auth.postgresPassword` and `auth.password`
- **Storage size**: Modify `primary.persistence.size`
- **Resources**: Adjust `primary.resources`
- **PostgreSQL settings**: Edit `primary.configuration`

After changes, upgrade with:

```bash
helm upgrade postgresql bitnami/postgresql -n postgres -f values.yaml
```

## Creating Additional Databases

```sql
-- Connect as postgres superuser
CREATE DATABASE myapp;
CREATE USER myapp_user WITH ENCRYPTED PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp_user;
```

## Backup & Restore

### Manual backup

```bash
# Port-forward first
kubectl port-forward -n postgres svc/postgresql 5432:5432

# Dump database
pg_dump -h localhost -U postgres -d default > backup.sql
```

### Restore

```bash
psql -h localhost -U postgres -d default < backup.sql
```

## Monitoring

Metrics exporter is enabled by default. Metrics available at:
- `postgresql.postgres.svc.cluster.local:9187/metrics`

To scrape with Prometheus, add this annotation to a ServiceMonitor or Prometheus scrape config.
