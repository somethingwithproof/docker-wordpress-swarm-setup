# CLAUDE.md

Production WordPress deployment on Docker Swarm with HA and SSL.

## Stack
- Docker Swarm
- Bash scripts

## Validation
```bash
# Validate stack file
docker stack config -c docker-stack.yml

# Check scripts
shellcheck scripts/*.sh

# Dry run
./scripts/galera-bootstrap.sh --dry-run
```

## Deploy
```bash
./scripts/setup-secrets.sh
./scripts/galera-bootstrap.sh
```
