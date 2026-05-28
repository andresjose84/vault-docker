# Configuración MFA TOTP (Login MFA)

Vault **Community** ≥ 1.10 soporta **Login MFA** con TOTP (Google Authenticator, Authy, etc.).

## Automatizado (recomendado)

Con Vault **inicializado, desprecintado** y `VAULT_TOKEN` (root) exportado:

```bash
export VAULT_ADDR='http://127.0.0.1:8201'
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)

# Variables opcionales
export MFA_USER='operador'
# El script genera una contraseña aleatoria si no defines MFA_PASSWORD
export MFA_PASSWORD='tu-contraseña-segura'

./scripts/configure-mfa-totp.sh
```

El script genera:

- Método `userpass`
- Usuario `operador`
- Entidad Identity + alias
- Método MFA TOTP y código QR (`vault/operador-totp-qr.png`)
- URL `otpauth://` en terminal
- **Login enforcement** que exige TOTP en todo login vía `userpass`

---

## Manual — comandos equivalentes

Ejecuta con `docker exec` o alias local. Sustituye `$VAULT_TOKEN` por tu root token.

### a) Habilitar autenticación userpass

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault auth enable userpass
```

Obtener el **accessor** del mount (necesario para MFA):

```bash
export USERPASS_ACCESSOR=$(docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault \
  vault auth list -format=json | jq -r '."userpass/".accessor')
echo "$USERPASS_ACCESSOR"
```

### b) Crear usuario de prueba `operador`

Política mínima de ejemplo:

```bash
docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault vault policy write operador-policy - <<'EOF'
# Política de ejemplo para el usuario operador (ajusta según necesidad)
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF
```

Usuario:

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  auth/userpass/users/operador \
  password='tu-contraseña-segura' \
  policies=operador-policy
```

### c) Entidad Identity y alias (requerido para TOTP)

```bash
export ENTITY_ID=$(docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -format=json identity/entity name="operador" | jq -r '.data.id')

docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write identity/entity-alias \
  name="operador" \
  canonical_id="$ENTITY_ID" \
  mount_accessor="$USERPASS_ACCESSOR"
```

### d) Método MFA TOTP y generación de QR / secreto

Crear método (nombre lógico: `operador-totp`):

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

Generar QR (PNG) y mostrar URL para la app autenticadora:

```bash
# Código QR en PNG
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -field=barcode \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID" | base64 -d > vault/operador-totp-qr.png

echo "QR guardado en: vault/operador-totp-qr.png"

# URL otpauth (copiar en Authy / escanear QR)
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  -field=url \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID"
```

> **Google Authenticator:** si SHA256 falla en algún cliente, recrea el método con `algorithm=SHA1`.

### e) Política de login: MFA obligatorio

Aplica TOTP a **todos** los logins del mount `userpass`:

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  identity/mfa/login-enforcement/require-totp-userpass \
  mfa_method_ids="$METHOD_ID" \
  auth_method_accessors="$USERPASS_ACCESSOR"
```

Para exigir MFA solo al usuario `operador` (por entidad):

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault write \
  identity/mfa/login-enforcement/require-totp-operador \
  mfa_method_ids="$METHOD_ID" \
  identity_entity_ids="$ENTITY_ID"
```

---

## Probar login con MFA

### CLI interactivo (dos fases: pide código TOTP)

```bash
export VAULT_ADDR='http://127.0.0.1:8201'
docker exec -it -e VAULT_ADDR vault vault login -method=userpass username=operador
# Introduce contraseña y luego el código de 6 dígitos de tu app
```

### CLI en una sola fase

```bash
# Sustituye 123456 por el código actual de tu autenticador
docker exec -it -e VAULT_ADDR vault vault login -method=userpass \
  username=operador \
  password='tu-contraseña-segura' \
  -mfa="${METHOD_ID}:123456"
```

### UI web

1. Abre [http://127.0.0.1:8201](http://127.0.0.1:8201)
2. Método: **Username**
3. Usuario: `operador` / contraseña configurada
4. Introduce el código TOTP cuando se solicite

---

## Referencias

- [Login MFA](https://developer.hashicorp.com/vault/docs/auth/login-mfa)
- [Tutorial MFA](https://developer.hashicorp.com/vault/tutorials/auth-methods/multi-factor-authentication)
