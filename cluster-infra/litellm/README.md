# LiteLLM

LiteLLM is an OpenAI-compatible proxy that provides a unified API for multiple LLM providers.

## Prerequisites

- PostgreSQL installed and running (see `../postgres/`)
- API keys for your LLM providers

## Installation

### 1. Configure secrets

Edit `secret.yaml` and update:

- `DATABASE_URL`: Update password to match what you set in `pg-setup.sql`
- `LITELLM_MASTER_KEY`: Generate with `openssl rand -hex 32`
- Add API keys for your providers (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)

### 2. Configure models

Edit `configmap.yaml` to configure your model list. Uncomment the providers you want to use.

### 3. Install

```bash
./install.sh
```

## Usage

### API Endpoints

| Endpoint | Description |
|----------|-------------|
| `http://litellm.home/health` | Health check |
| `http://litellm.home/v1/models` | List available models |
| `http://litellm.home/v1/chat/completions` | Chat completions (OpenAI-compatible) |
| `http://litellm.home/ui` | Web dashboard |

### Example requests

```bash
# Health check
curl http://litellm.home/health

# List models
curl http://litellm.home/v1/models \
  -H "Authorization: Bearer sk-your-master-key"

# Chat completion
curl http://litellm.home/v1/chat/completions \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Use with OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-your-master-key",
    base_url="http://litellm.home/v1"
)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

## Adding API Keys

To add more provider API keys after installation:

1. Edit `secret.yaml` and add the new keys
2. Uncomment the corresponding env vars in `deployment.yaml`
3. Apply the changes:

```bash
kubectl apply -f secret.yaml
kubectl apply -f deployment.yaml
kubectl rollout restart deployment/litellm -n litellm
```

## Troubleshooting

### View logs

```bash
kubectl logs -n litellm -l app=litellm -f
```

### Check database connection

```bash
kubectl exec -n litellm deployment/litellm -- env | grep DATABASE_URL
```

### Restart deployment

```bash
kubectl rollout restart deployment/litellm -n litellm
```

## Uninstallation

```bash
./uninstall.sh
```

This preserves the database. To fully clean up:

```bash
kubectl port-forward -n postgres svc/postgresql 5432:5432
psql -h localhost -U postgres -c 'DROP DATABASE litellm;'
psql -h localhost -U postgres -c 'DROP USER litellm;'
```
