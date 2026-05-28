# vault-docker

<p align="center">
  <img src="./img/hashicorp-vault_logo.png" alt="HashiCorp Vault logo" style="max-width: 260px; width: 100%; height: auto;">
</p>

Despliegue local de **HashiCorp Vault** en Docker para macOS (Apple Silicon / Intel), con persistencia, UI web y **Login MFA TOTP**.

Local **HashiCorp Vault** deployment on Docker for macOS (Apple Silicon / Intel), with persistent storage, web UI, and **MFA TOTP Login**.

## Quick Start / Inicio rapido

```bash
VAULT_HOST_PORT=8201 docker compose up -d
# ES: sigue GUIA-POST-DESPLIEGUE.md (init, unseal) y luego ./scripts/configure-mfa-totp.sh
# EN: follow GUIDE-POST-DEPLOYMENT.md (init, unseal) then ./scripts/configure-mfa-totp.sh
```

## Documentation / Documentacion

### Español

- [Guia post-despliegue](./GUIA-POST-DESPLIEGUE.md)
- [Guia MFA TOTP](./GUIA-MFA-TOTP.md)

### English

- [Post-deployment guide](./GUIDE-POST-DEPLOYMENT.md)
- [MFA TOTP guide](./GUIDE-MFA-TOTP.md)

## Structure / Estructura

| File / archivo | Description / descripcion |
|----------------|---------------------------|
| `docker-compose.yml` | Vault service, volumes, `IPC_LOCK`, host port 8201 -> container 8200 |
| `config/vault.hcl` | File storage, TCP listener, UI, TLS disabled (dev only) |
| `vault/data/` | Persistent server data |
| `GUIA-POST-DESPLIEGUE.md` | Post-deployment guide in Spanish |
| `GUIA-MFA-TOTP.md` | MFA TOTP guide in Spanish |
| `GUIDE-POST-DEPLOYMENT.md` | Post-deployment guide in English |
| `GUIDE-MFA-TOTP.md` | MFA TOTP guide in English |
| `scripts/configure-mfa-totp.sh` | Automation script for MFA setup |

Generated from `PROMPT.md`.
