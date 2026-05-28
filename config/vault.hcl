# Configuración de Vault para entorno local en macOS (Docker)
# ADVERTENCIA: tls_disable = true solo es aceptable en desarrollo local.

ui = true

# En contenedores Docker, mlock suele no estar disponible sin privilegios extra
disable_mlock = true

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# Dirección que el cliente usará desde el host (Mac)
api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

# Logs en stdout para facilitar depuración con: docker compose logs -f vault
log_level = "info"
