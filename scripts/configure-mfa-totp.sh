#!/usr/bin/env bash
# Configura userpass + usuario operador + Login MFA TOTP obligatorio
# Requisitos: Vault inicializado, desprecintado, VAULT_TOKEN (root) definido
set -euo pipefail

CONTAINER="${VAULT_CONTAINER:-vault}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
MFA_USER="${MFA_USER:-operador}"
# Define MFA_PASSWORD en el entorno al ejecutar el script en entornos nuevos
MFA_PASSWORD="${MFA_PASSWORD:-}"
if [[ -z "$MFA_PASSWORD" ]]; then
  MFA_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
  echo "Contraseña generada para ${MFA_USER}: ${MFA_PASSWORD}" >&2
fi
MFA_METHOD_NAME="${MFA_METHOD_NAME:-operador-totp}"
MFA_ISSUER="${MFA_ISSUER:-Vault-Local}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QR_OUTPUT="${REPO_ROOT}/vault/${MFA_USER}-totp-qr.png"

vault_cmd() {
  docker exec -e VAULT_TOKEN -e VAULT_ADDR "$CONTAINER" vault "$@"
}

log() { printf '\n==> %s\n' "$*"; }

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "ERROR: exporta VAULT_TOKEN (root token) antes de ejecutar este script." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: el contenedor '$CONTAINER' no está en ejecución. Ejecuta: docker compose up -d" >&2
  exit 1
fi

log "Comprobando estado de Vault"
vault_cmd status | grep -q 'Sealed.*false' || {
  echo "ERROR: Vault está sellado. Desprecíntalo primero (ver GUIA-POST-DESPLIEGUE.md)." >&2
  exit 1
}

log "Habilitando auth method userpass (si no existe)"
if vault_cmd auth list -format=json | jq -e '."userpass/"' >/dev/null 2>&1; then
  echo "userpass ya está habilitado"
else
  vault_cmd auth enable userpass
fi

USERPASS_ACCESSOR="$(vault_cmd auth list -format=json | jq -r '."userpass/".accessor // ."auth/userpass/".accessor')"
if [[ -z "$USERPASS_ACCESSOR" || "$USERPASS_ACCESSOR" == "null" ]]; then
  echo "ERROR: no se pudo obtener el accessor de userpass." >&2
  exit 1
fi
log "Accessor userpass: $USERPASS_ACCESSOR"

log "Creando política operador-policy"
docker exec -e VAULT_TOKEN "$CONTAINER" sh -c 'cat > /tmp/operador-policy.hcl <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF
vault policy write operador-policy /tmp/operador-policy.hcl'

log "Creando usuario '$MFA_USER'"
vault_cmd write "auth/userpass/users/${MFA_USER}" \
  password="$MFA_PASSWORD" \
  policies=operador-policy

log "Creando entidad Identity y alias"
ENTITY_ID="$(vault_cmd write -format=json "identity/entity" name="$MFA_USER" | jq -r '.data.id')"
vault_cmd write identity/entity-alias \
  name="$MFA_USER" \
  canonical_id="$ENTITY_ID" \
  mount_accessor="$USERPASS_ACCESSOR"
log "ENTITY_ID=$ENTITY_ID"

log "Configurando método MFA TOTP"
METHOD_ID="$(vault_cmd write -field=method_id \
  identity/mfa/method/totp \
  issuer="$MFA_ISSUER" \
  period=30 \
  key_size=20 \
  algorithm=SHA256 \
  digits=6)"
log "METHOD_ID=$METHOD_ID"

log "Generando QR y URL otpauth para $MFA_USER"
mkdir -p "$(dirname "$QR_OUTPUT")"
vault_cmd write -field=barcode \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID" | base64 -d >"$QR_OUTPUT"
echo "QR guardado en: $QR_OUTPUT"

if OTP_URL="$(vault_cmd write -format=json \
  identity/mfa/method/totp/admin-generate \
  method_id="$METHOD_ID" \
  entity_id="$ENTITY_ID" 2>/dev/null | jq -r '.data.url // .data.barcode // empty')" && [[ -n "$OTP_URL" ]]; then
  echo ""
  echo "Datos TOTP (escanea el QR o usa la URL si tu app lo permite):"
  echo "$OTP_URL"
  echo ""
else
  echo ""
  echo "Escanea el QR en: $QR_OUTPUT"
  echo "(La URL otpauth no está disponible en esta versión; usa el PNG.)"
  echo ""
fi

log "Aplicando login enforcement: TOTP obligatorio en userpass"
vault_cmd write identity/mfa/login-enforcement/require-totp-userpass \
  mfa_method_ids="$METHOD_ID" \
  auth_method_accessors="$USERPASS_ACCESSOR"

log "Configuración completada"
cat <<EOF

Próximos pasos:
  1. Abre el QR: open "$QR_OUTPUT"
  2. Prueba login:
     docker exec -it -e VAULT_ADDR=$VAULT_ADDR $CONTAINER \\
       vault login -method=userpass username=$MFA_USER

Credenciales de prueba:
  Usuario:  $MFA_USER
  Password: $MFA_PASSWORD

EOF
