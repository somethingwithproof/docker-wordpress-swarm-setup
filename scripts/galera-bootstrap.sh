#!/bin/bash
# =============================================================================
# Galera Cluster Bootstrap Automation Script
# =============================================================================
# This script automates the safe bootstrapping of a MariaDB Galera cluster
# in Docker Swarm. It handles:
# - Initial cluster bootstrap (first node)
# - Detecting existing cluster state
# - Safe restart after full cluster shutdown
# - Graceful scaling after bootstrap
#
# Usage: ./scripts/galera-bootstrap.sh [--force]
# =============================================================================

set -euo pipefail

# Configuration
STACK_NAME="${STACK_NAME:-wordpress}"
DB_SERVICE="${DB_SERVICE:-wpdbcluster}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-stack.yml}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-120}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"

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

# Check if Docker Swarm is initialized
check_swarm() {
  log_info "Checking Docker Swarm status..."
  if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
    log_error "Docker Swarm is not initialized. Run 'docker swarm init' first."
    exit 1
  fi
  log_success "Docker Swarm is active"
}

# Check if secrets exist
check_secrets() {
  log_info "Checking required secrets..."
  local missing_secrets=()

  for secret in mysql_root_password mysql_password redis_password traefik_dashboard_auth; do
    if ! docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -gt 0 ]; then
    log_error "Missing Docker secrets: ${missing_secrets[*]}"
    log_info "Create secrets from files in ./secrets/ directory:"
    for secret in "${missing_secrets[@]}"; do
      echo "  docker secret create $secret ./secrets/${secret}.txt"
    done
    exit 1
  fi
  log_success "All required secrets exist"
}

# Check if cluster is already running
check_existing_cluster() {
  log_info "Checking for existing Galera cluster..."

  local running_replicas
  running_replicas=$(docker service ls --filter "name=${STACK_NAME}_${DB_SERVICE}" --format '{{.Replicas}}' 2>/dev/null | cut -d'/' -f1 || echo "0")

  if [ "$running_replicas" -gt 0 ]; then
    log_info "Found $running_replicas running database replicas"

    # Check cluster health
    local container_id
    container_id=$(docker ps -q --filter "name=${STACK_NAME}_${DB_SERVICE}" | head -1)

    if [ -n "$container_id" ]; then
      local cluster_size
      cluster_size=$(docker exec "$container_id" mysql -u root -p"$(cat /run/secrets/mysql_root_password 2>/dev/null || echo '')" \
        -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | grep -oP '\d+$' || echo "0")

      if [ "$cluster_size" -gt 0 ]; then
        log_success "Galera cluster is healthy with $cluster_size nodes"
        return 0
      fi
    fi
  fi

  return 1
}

# Create bootstrap service configuration
create_bootstrap_config() {
  log_info "Creating bootstrap configuration..."

  # Create a temporary compose file with bootstrap flag enabled
  cat >/tmp/galera-bootstrap.yml <<'EOF'
services:
  wpdbcluster:
    environment:
      MARIADB_GALERA_CLUSTER_BOOTSTRAP: "yes"
    deploy:
      replicas: 1
EOF

  log_success "Bootstrap configuration created"
}

# Start bootstrap node
start_bootstrap_node() {
  log_info "Starting Galera bootstrap node..."

  # Deploy with single replica and bootstrap flag
  docker stack deploy \
    -c "$COMPOSE_FILE" \
    -c /tmp/galera-bootstrap.yml \
    "$STACK_NAME"

  log_info "Waiting for bootstrap node to be healthy..."

  local elapsed=0
  while [ "$elapsed" -lt "$BOOTSTRAP_TIMEOUT" ]; do
    local container_id
    container_id=$(docker ps -q --filter "name=${STACK_NAME}_${DB_SERVICE}" | head -1)

    if [ -n "$container_id" ]; then
      # Check if MariaDB is accepting connections
      if docker exec "$container_id" mysqladmin ping -h localhost --silent 2>/dev/null; then
        log_success "Bootstrap node is ready!"
        return 0
      fi
    fi

    sleep "$HEALTH_CHECK_INTERVAL"
    elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    echo -n "."
  done

  log_error "Bootstrap node failed to become healthy within ${BOOTSTRAP_TIMEOUT}s"
  return 1
}

# Scale cluster to full size
scale_cluster() {
  local replicas="${1:-3}"

  log_info "Scaling Galera cluster to $replicas replicas..."

  # Remove bootstrap configuration and scale up
  docker stack deploy \
    -c "$COMPOSE_FILE" \
    "$STACK_NAME"

  log_info "Waiting for all nodes to join the cluster..."

  local elapsed=0
  local scale_timeout=$((BOOTSTRAP_TIMEOUT * 2))

  while [ $elapsed -lt $scale_timeout ]; do
    local container_id
    container_id=$(docker ps -q --filter "name=${STACK_NAME}_${DB_SERVICE}" | head -1)

    if [ -n "$container_id" ]; then
      local cluster_size
      cluster_size=$(docker exec "$container_id" mysql -u root -p"$(docker exec "$container_id" cat /run/secrets/mysql_root_password 2>/dev/null)" \
        -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | grep -oP '\d+$' || echo "0")

      if [ "$cluster_size" -ge "$replicas" ]; then
        log_success "Galera cluster scaled to $cluster_size nodes!"
        return 0
      fi

      log_info "Current cluster size: $cluster_size / $replicas"
    fi

    sleep "$HEALTH_CHECK_INTERVAL"
    elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
  done

  log_warn "Cluster did not reach full size within timeout. Check logs with:"
  echo "  docker service logs ${STACK_NAME}_${DB_SERVICE}"
}

# Cleanup temporary files
cleanup() {
  rm -f /tmp/galera-bootstrap.yml
}

# Main execution
main() {
  local force_bootstrap=false

  if [ "${1:-}" = "--force" ]; then
    force_bootstrap=true
    log_warn "Force bootstrap requested. This will reinitialize the cluster!"
  fi

  echo "=============================================="
  echo "  Galera Cluster Bootstrap Script"
  echo "=============================================="
  echo

  # Pre-flight checks
  check_swarm
  check_secrets

  # Check for existing cluster
  if ! $force_bootstrap && check_existing_cluster; then
    log_info "Cluster is already running. Use --force to reinitialize."
    exit 0
  fi

  # Setup cleanup trap
  trap cleanup EXIT

  # Bootstrap process
  create_bootstrap_config

  if start_bootstrap_node; then
    log_info "Bootstrap successful. Removing bootstrap flag and scaling..."
    sleep 5 # Allow bootstrap node to stabilize
    scale_cluster 3
  else
    log_error "Bootstrap failed. Check Docker logs for details:"
    echo "  docker service logs ${STACK_NAME}_${DB_SERVICE}"
    exit 1
  fi

  echo
  echo "=============================================="
  log_success "Galera cluster bootstrap complete!"
  echo "=============================================="
  echo
  echo "Useful commands:"
  echo "  Check cluster status: docker exec \$(docker ps -q -f name=${STACK_NAME}_${DB_SERVICE} | head -1) mysql -u root -p -e \"SHOW STATUS LIKE 'wsrep_%';\""
  echo "  View service logs:    docker service logs ${STACK_NAME}_${DB_SERVICE}"
  echo "  Scale cluster:        docker service scale ${STACK_NAME}_${DB_SERVICE}=3"
}

main "$@"
