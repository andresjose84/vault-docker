# Step-by-Step Guide — Vault on Docker (macOS)

Local setup with UI enabled, persistent storage, and ready for Login MFA with TOTP (Vault >= 1.10).

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) for Mac
- Terminal (`zsh` / `bash`)

## a) Start the container

From the repository root:

```bash
cd /Users/ajsm/Developer/GitHub/vault-docker

# Create data directory if it does not exist
mkdir -p vault/data

# Start Vault in the background
docker compose up -d

# Verify the container is running
docker compose ps

# Check logs (optional)
docker compose logs -f vault
```

Export the server address (useful for local CLI or scripts):

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Open the UI in your browser: [http://127.0.0.1:8200](http://127.0.0.1:8200)

---

## b) Initialize Vault and save keys

Run this **only once**, when the server is **sealed** and **not initialized**.

```bash
# Initialize: generates 5 unseal keys and 1 root token (default threshold: 3)
docker exec -it vault vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json | tee vault/init-keys.json
```

> **Important:** store `vault/init-keys.json` in a secure location (password manager, vault). **Do not commit it to Git.** The file is already in `.gitignore`.

Extract useful values (requires `jq`):

```bash
# Root token
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)

# First 3 unseal keys (threshold = 3)
export UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault/init-keys.json)
export UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault/init-keys.json)
export UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault/init-keys.json)
```

---

## c) Unseal Vault

After each container restart, Vault goes back to **sealed** state. You must provide at least **3** unseal keys (based on your configured threshold).

```bash
docker exec -it vault vault operator unseal "$UNSEAL_KEY_1"
docker exec -it vault vault operator unseal "$UNSEAL_KEY_2"
docker exec -it vault vault operator unseal "$UNSEAL_KEY_3"

# Check status: Sealed must be false
docker exec -it vault vault status
```

Authenticate with the root token (initial administration):

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault token lookup
```

---

## Next step: MFA TOTP

Configure userpass, the `operador` user, and mandatory Login MFA:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)
./scripts/configure-mfa-totp.sh
```

See [GUIDE-MFA-TOTP.md](./GUIDE-MFA-TOTP.md) for full command details and login tests.

---

## Useful commands

```bash
# Stop
docker compose down

# Stop and remove anonymous volumes (does NOT delete host ./vault/data)
docker compose down -v

# Restart after config changes
docker compose restart vault
```

## Security notes

- `tls_disable = true` in `config/vault.hcl` is **for local development only**.
- In production: enable TLS, use HA storage (Raft/Consul), rotate tokens, and apply least-privilege policies.
- Revoke or strictly limit use of the **root token** right after initial setup.
