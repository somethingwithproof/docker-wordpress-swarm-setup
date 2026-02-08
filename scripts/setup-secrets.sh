#!/bin/bash
# =============================================================================
# Secrets Setup Script for WordPress Swarm Deployment
# =============================================================================
# This script generates secure passwords and creates Docker secrets for the
# WordPress Swarm stack. Run this before your first deployment.
#
# Usage: ./scripts/setup-secrets.sh [--force]
# =============================================================================

set -euo pipefail

# Configuration
SECRETS_DIR="${SECRETS_DIR:-./secrets}"
PASSWORD_LENGTH="${PASSWORD_LENGTH:-32}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Generate a cryptographically secure password
generate_password() {
  local length="${1:-$PASSWORD_LENGTH}"
  # Use /dev/urandom for secure randomness, base64 encode, remove special chars
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# Check if htpasswd is available
check_htpasswd() {
  if command -v htpasswd &>/dev/null; then
    return 0
  elif command -v openssl &>/dev/null; then
    return 1
  else
    log_error "Neither htpasswd nor openssl found. Please install apache2-utils or openssl."
    exit 1
  fi
}

# Generate htpasswd hash
generate_htpasswd() {
  local username="$1"
  local password="$2"

  if command -v htpasswd &>/dev/null; then
    htpasswd -nb "$username" "$password"
  else
    # Fallback to openssl for apr1 hash
    local salt
    salt=$(openssl rand -base64 8 | tr -dc 'A-Za-z0-9' | head -c 8)
    local hash
    hash=$(openssl passwd -apr1 -salt "$salt" "$password")
    echo "${username}:${hash}"
  fi
}

# Check if secrets already exist
check_existing_secrets() {
  local force="$1"
  local existing=()

  for secret in mysql_root_password mysql_password redis_password traefik_dashboard_auth; do
    local file="${SECRETS_DIR}/${secret}.txt"
    if [ -f "$file" ]; then
      # Check if it's a placeholder
      if grep -q "REPLACE_WITH" "$file" 2>/dev/null; then
        continue
      fi
      existing+=("$secret")
    fi
  done

  if [ ${#existing[@]} -gt 0 ] && [ "$force" != "true" ]; then
    log_warn "The following secrets already exist: ${existing[*]}"
    log_warn "Use --force to regenerate all secrets (this will overwrite existing values)"
    return 1
  fi

  return 0
}

# Create secrets directory
create_secrets_dir() {
  if [ ! -d "$SECRETS_DIR" ]; then
    log_info "Creating secrets directory: $SECRETS_DIR"
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
  fi
}

# Generate all secrets
generate_secrets() {
  log_info "Generating secure passwords..."

  # MySQL root password
  local mysql_root_pass
  mysql_root_pass=$(generate_password)
  echo -n "$mysql_root_pass" >"${SECRETS_DIR}/mysql_root_password.txt"
  chmod 600 "${SECRETS_DIR}/mysql_root_password.txt"
  log_success "Generated MySQL root password"

  # MySQL WordPress user password
  local mysql_user_pass
  mysql_user_pass=$(generate_password)
  echo -n "$mysql_user_pass" >"${SECRETS_DIR}/mysql_password.txt"
  chmod 600 "${SECRETS_DIR}/mysql_password.txt"
  log_success "Generated MySQL user password"

  # Redis password
  local redis_pass
  redis_pass=$(generate_password)
  echo -n "$redis_pass" >"${SECRETS_DIR}/redis_password.txt"
  chmod 600 "${SECRETS_DIR}/redis_password.txt"
  log_success "Generated Redis password"

  # Traefik dashboard auth
  log_info "Setting up Traefik dashboard authentication..."

  local traefik_user
  local traefik_pass

  read -rp "Enter Traefik dashboard username [admin]: " traefik_user
  traefik_user="${traefik_user:-admin}"

  read -rsp "Enter Traefik dashboard password (leave empty to generate): " traefik_pass
  echo

  if [ -z "$traefik_pass" ]; then
    traefik_pass=$(generate_password 24)
    log_info "Generated Traefik password: $traefik_pass"
    log_warn "Save this password - it won't be shown again!"
  fi

  local htpasswd_entry
  htpasswd_entry=$(generate_htpasswd "$traefik_user" "$traefik_pass")
  echo "$htpasswd_entry" >"${SECRETS_DIR}/traefik_dashboard_auth.txt"
  chmod 600 "${SECRETS_DIR}/traefik_dashboard_auth.txt"
  log_success "Generated Traefik dashboard auth"
}

# Create Docker secrets (if in Swarm mode)
create_docker_secrets() {
  # Check if Docker Swarm is active
  if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
    log_info "Docker Swarm not active. Skipping Docker secret creation."
    log_info "Secrets have been saved to $SECRETS_DIR/"
    log_info "Run 'docker swarm init' and then create secrets with:"
    echo
    for secret in mysql_root_password mysql_password redis_password traefik_dashboard_auth; do
      echo "  docker secret create $secret ${SECRETS_DIR}/${secret}.txt"
    done
    return
  fi

  log_info "Creating Docker secrets..."

  for secret in mysql_root_password mysql_password redis_password traefik_dashboard_auth; do
    # Remove existing secret if it exists
    if docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
      log_warn "Secret '$secret' already exists in Docker. Skipping."
      log_info "To update, remove it first: docker secret rm $secret"
      continue
    fi

    docker secret create "$secret" "${SECRETS_DIR}/${secret}.txt"
    log_success "Created Docker secret: $secret"
  done
}

# Print summary
print_summary() {
  echo
  echo "=============================================="
  echo -e "${GREEN}  Secrets Setup Complete!${NC}"
  echo "=============================================="
  echo
  echo "Secret files created in: $SECRETS_DIR/"
  echo
  echo "IMPORTANT SECURITY NOTES:"
  echo "  1. These passwords are stored in plain text in $SECRETS_DIR/"
  echo "  2. Ensure this directory is NOT committed to version control"
  echo "  3. Back up these passwords securely (password manager, encrypted storage)"
  echo "  4. The secrets directory has restricted permissions (700)"
  echo
  echo "Next steps:"
  echo "  1. Update 'your-domain.com' in docker-stack.yml with your domain"
  echo "  2. Update 'YOUR_REAL_EMAIL@example.com' for Let's Encrypt"
  echo "  3. Run ./scripts/galera-bootstrap.sh to deploy the stack"
  echo
}

# Main execution
main() {
  local force=false

  if [ "${1:-}" = "--force" ]; then
    force=true
    log_warn "Force mode enabled. All secrets will be regenerated."
  fi

  echo "=============================================="
  echo "  WordPress Swarm Secrets Setup"
  echo "=============================================="
  echo

  # Check for existing secrets
  if ! check_existing_secrets "$force"; then
    exit 1
  fi

  # Create directory and generate secrets
  create_secrets_dir
  generate_secrets

  # Create Docker secrets if Swarm is active
  create_docker_secrets

  # Print summary
  print_summary
}

main "$@"
