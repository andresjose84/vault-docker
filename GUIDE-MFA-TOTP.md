# MFA TOTP Configuration (Login MFA)

Vault **Community** >= 1.10 supports **Login MFA** with TOTP (Google Authenticator, Authy, etc.).

## Automated (recommended)

With Vault **initialized, unsealed**, and `VAULT_TOKEN` (root) exported:

```bash
export VAULT_ADDR='http://127.0.0.1:8201'
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)

# Optional variables
export MFA_USER='operador'
# The script generates a random password if MFA_PASSWORD is not set
export MFA_PASSWORD='your-secure-password'

./scripts/configure-mfa-totp.sh
```

The script creates:

- `userpass` auth method
- `operador` user
- Identity entity + alias
- MFA TOTP method and QR code (`vault/operador-totp-qr.png`)
- `otpauth://` URL in terminal
- **Login enforcement** that requires TOTP for every `userpass` login

---

## Manual — equivalent commands

Run with `docker exec` or a local alias. Replace `$VAULT_TOKEN` with your root token.

### a) Enable userpass auth

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault auth enable userpass
```

Get the mount **accessor** (required for MFA):

```bash
export USERPASS_ACCESSOR=$(docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault \
  vault auth list -format=json | jq -r '."userpass/".accessor')
echo "$USERPASS_ACCESSOR"
```

### b) Create test user `operador`

Example minimum policy:

```bash
docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault vault policy write operador-policy - <<'EOF'
# Example policy for operador (adjust as needed)
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF
```

User:

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  auth/userpass/users/operador \
  password='your-secure-password' \
  policies=operador-policy
```

### c) Identity entity and alias (required for TOTP)

```bash
export ENTITY_ID=$(docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -format=json identity/entity name="operador" | jq -r '.data.id')

docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write identity/entity-alias \
  name="operador" \
  canonical_id="$ENTITY_ID" \
  mount_accessor="$USERPASS_ACCESSOR"
```

### d) MFA TOTP method and QR/secret generation

Create method (logical name: `operador-totp`):

```bash
export METHOD_ID=$(docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -field=method_id \
  identity/mfa/method/totp \
  issuer="Vault-Local" \
  period=30 \
  key_size=20 \
  algorithm=SHA256 \
  digits=6)
echo "METHOD_ID=$METHOD_ID"
```

Generate QR (PNG) and print URL for authenticator app:

```bash
# QR code as PNG
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -field=barcode \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID" | base64 -d > vault/operador-totp-qr.png

echo "QR saved at: vault/operador-totp-qr.png"

# otpauth URL (copy to Authy / scan QR)
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -field=url \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID"
```

> **Google Authenticator:** if SHA256 fails in your client, recreate the method with `algorithm=SHA1`.

### e) Login policy: mandatory MFA

Apply TOTP to **all** logins on the `userpass` mount:

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  identity/mfa/login-enforcement/require-totp-userpass \
  mfa_method_ids="$METHOD_ID" \
  auth_method_accessors="$USERPASS_ACCESSOR"
```

Require MFA only for user `operador` (by entity):

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  identity/mfa/login-enforcement/require-totp-operador \
  mfa_method_ids="$METHOD_ID" \
  identity_entity_ids="$ENTITY_ID"
```

---

## Test MFA login

### Interactive CLI (two phases: prompts for TOTP code)

```bash
export VAULT_ADDR='http://127.0.0.1:8201'
docker exec -it -e VAULT_ADDR vault vault login -method=userpass username=operador
# Enter password and then the 6-digit code from your app
```

### One-shot CLI login

```bash
# Replace 123456 with the current code from your authenticator
docker exec -it -e VAULT_ADDR vault vault login -method=userpass \
  username=operador \
  password='your-secure-password' \
  -mfa="${METHOD_ID}:123456"
```

### Web UI

1. Open [http://127.0.0.1:8201](http://127.0.0.1:8201)
2. Method: **Username**
3. User: `operador` / configured password
4. Enter TOTP code when prompted

---

## References

- [Login MFA](https://developer.hashicorp.com/vault/docs/auth/login-mfa)
- [MFA tutorial](https://developer.hashicorp.com/vault/tutorials/auth-methods/multi-factor-authentication)
