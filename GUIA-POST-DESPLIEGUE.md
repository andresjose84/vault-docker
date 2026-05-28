# Guía paso a paso — Vault en Docker (macOS)

Entorno local con UI habilitada, almacenamiento persistente y preparado para Login MFA con TOTP (Vault ≥ 1.10).

## Requisitos previos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) para Mac
- Terminal (`zsh` / `bash`)

## a) Levantar el contenedor

Desde la raíz del repositorio:

```bash
cd /Users/ajsm/Developer/GitHub/vault-docker

# Crear directorio de datos si no existe
mkdir -p vault/data

# Iniciar Vault en segundo plano
VAULT_HOST_PORT=8201 docker compose up -d

# Verificar que el contenedor está en ejecución
docker compose ps

# Revisar logs (opcional)
docker compose logs -f vault
```

Exporta la dirección del servidor (útil para el CLI local o scripts):

```bash
export VAULT_ADDR='http://127.0.0.1:8201'
```

Abre la UI en el navegador: [http://127.0.0.1:8201](http://127.0.0.1:8201)

---

## b) Inicializar Vault y guardar llaves

Solo se ejecuta **una vez**, cuando el servidor está **sellado (sealed)** y **no inicializado**.

```bash
# Inicializar: genera 5 unseal keys y 1 root token (threshold por defecto: 3)
docker exec -it vault vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json | tee vault/init-keys.json
```

> **Importante:** guarda `vault/init-keys.json` en un lugar seguro (gestor de contraseñas, caja fuerte). **No lo subas a Git.** El archivo ya está en `.gitignore`.

Extrae valores útiles (requiere `jq`):

```bash
# Root token
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)

# Primeras 3 unseal keys (threshold = 3)
export UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault/init-keys.json)
export UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault/init-keys.json)
export UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault/init-keys.json)
```

---

## c) Desprecintar (unseal) Vault

Tras cada reinicio del contenedor, Vault vuelve a estado **sealed**. Debes aplicar al menos **3** unseal keys (según el threshold configurado).

```bash
docker exec -it vault vault operator unseal "$UNSEAL_KEY_1"
docker exec -it vault vault operator unseal "$UNSEAL_KEY_2"
docker exec -it vault vault operator unseal "$UNSEAL_KEY_3"

# Comprobar estado: Sealed debe ser false
docker exec -it vault vault status
```

Autenticación con root token (administración inicial):

```bash
docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault token lookup
```

---

## Siguiente paso: MFA TOTP

Configura userpass, usuario `operador` y Login MFA obligatorio:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' vault/init-keys.json)
./scripts/configure-mfa-totp.sh
```

Consulta [GUIA-MFA-TOTP.md](./GUIA-MFA-TOTP.md) para el detalle de cada comando y pruebas de login.

---

## Comandos útiles

```bash
# Detener
docker compose down

# Detener y eliminar volúmenes anónimos (NO borra ./vault/data del host)
docker compose down -v

# Reiniciar tras cambios en config
docker compose restart vault
```

## Notas de seguridad

- `tls_disable = true` en `config/vault.hcl` es **solo para desarrollo local**.
- En producción: habilita TLS, usa almacenamiento HA (Raft/Consul), rotación de tokens y políticas mínimas.
- Revoca o limita el uso del **root token** en cuanto termines la configuración inicial.
