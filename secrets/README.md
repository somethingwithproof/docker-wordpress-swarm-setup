# Secrets Directory

This directory stores secret files for the WordPress Swarm deployment.

> **Warning:** Never commit real passwords to version control. The `.gitignore` file excludes `*.txt` files from this directory.

## Quick Setup

Generate all secrets automatically:

```bash
./scripts/setup-secrets.sh
```

## Secret Files

| File | Description | Format |
|------|-------------|--------|
| `mysql_root_password.txt` | MariaDB root password | Plain text |
| `mysql_password.txt` | WordPress database user password | Plain text |
| `redis_password.txt` | Redis authentication password | Plain text |
| `traefik_dashboard_auth.txt` | Traefik dashboard credentials | htpasswd format |

## Manual Setup

If you prefer to create secrets manually:

### 1. Generate Passwords

```bash
# Generate secure random passwords
openssl rand -base64 32 > mysql_root_password.txt
openssl rand -base64 32 > mysql_password.txt
openssl rand -base64 32 > redis_password.txt
```

### 2. Create Traefik Auth

Requires `htpasswd` from `apache2-utils`:

```bash
# Install htpasswd (Debian/Ubuntu)
apt-get install apache2-utils

# Generate auth file
htpasswd -nb admin YOUR_SECURE_PASSWORD > traefik_dashboard_auth.txt
```

### 3. Set File Permissions

```bash
chmod 600 *.txt
```

## Docker Secrets

After creating the files, register them with Docker Swarm:

```bash
# Create secrets
docker secret create mysql_root_password mysql_root_password.txt
docker secret create mysql_password mysql_password.txt
docker secret create redis_password redis_password.txt
docker secret create traefik_dashboard_auth traefik_dashboard_auth.txt

# Verify
docker secret ls
```

## Updating Secrets

Docker secrets are immutable. To update a secret:

```bash
# Remove old secret (requires removing services that use it)
docker secret rm mysql_password

# Create new secret
docker secret create mysql_password mysql_password.txt

# Redeploy stack
docker stack deploy -c docker-stack.yml wordpress
```

## Security Best Practices

1. **Backup passwords** to a secure location (password manager, encrypted storage)
2. **Restrict file permissions** — files should be readable only by owner (`chmod 600`)
3. **Rotate passwords** periodically, especially after team member departures
4. **Audit access** — review who has access to secrets
