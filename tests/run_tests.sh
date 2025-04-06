#!/bin/bash
# WordPress Swarm Deployment Test Suite
# This script runs a series of tests to verify the Docker Swarm deployment

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    echo -e "\n${YELLOW}Running test: ${test_name}${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Run the test command
    eval "$test_command"
    local actual_exit_code=$?
    
    # Check if the exit code matches the expected exit code
    if [ $actual_exit_code -eq $expected_exit_code ]; then
        echo -e "${GREEN}✓ Test passed: ${test_name}${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ Test failed: ${test_name}${NC}"
        echo -e "${RED}  Expected exit code: ${expected_exit_code}, Actual: ${actual_exit_code}${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Function to check if Docker Swarm is active
check_swarm_active() {
    docker info | grep -q "Swarm: active"
    return $?
}

# Function to check if a service is running
check_service_running() {
    local service_name="$1"
    docker service ls --filter "name=${service_name}" --format "{{.Name}}" | grep -q "${service_name}"
    return $?
}

# Function to check if a service has the expected number of replicas
check_service_replicas() {
    local service_name="$1"
    local expected_replicas="$2"
    local actual_replicas=$(docker service ls --filter "name=${service_name}" --format "{{.Replicas}}" | cut -d'/' -f1)
    
    if [ "$actual_replicas" -eq "$expected_replicas" ]; then
        return 0
    else
        echo "Expected ${expected_replicas} replicas, but found ${actual_replicas}"
        return 1
    fi
}

# Function to check if a service is healthy
check_service_health() {
    local service_name="$1"
    local unhealthy_tasks=$(docker service ps ${service_name} --format "{{.CurrentState}}" | grep -c "Unhealthy" || true)
    
    if [ "$unhealthy_tasks" -eq 0 ]; then
        return 0
    else
        echo "Found ${unhealthy_tasks} unhealthy tasks for service ${service_name}"
        return 1
    fi
}

# Function to check if a port is open
check_port_open() {
    local host="$1"
    local port="$2"
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}"
    return $?
}

# Function to check if a URL returns a 200 status code
check_url_status() {
    local url="$1"
    local expected_status="${2:-200}"
    local status=$(curl -s -o /dev/null -w "%{http_code}" ${url})
    
    if [ "$status" -eq "$expected_status" ]; then
        return 0
    else
        echo "Expected status ${expected_status}, but got ${status}"
        return 1
    fi
}

# Function to check if a container's logs contain a specific string
check_logs_contain() {
    local service_name="$1"
    local search_string="$2"
    local container_id=$(docker ps --filter "name=${service_name}" --format "{{.ID}}" | head -1)
    
    if [ -z "$container_id" ]; then
        echo "No container found for service ${service_name}"
        return 1
    fi
    
    docker logs ${container_id} | grep -q "${search_string}"
    return $?
}

# Function to check if a secret exists
check_secret_exists() {
    local secret_name="$1"
    docker secret ls --filter "name=${secret_name}" --format "{{.Name}}" | grep -q "${secret_name}"
    return $?
}

# Function to check if a network exists
check_network_exists() {
    local network_name="$1"
    docker network ls --filter "name=${network_name}" --format "{{.Name}}" | grep -q "${network_name}"
    return $?
}

# Function to check if a volume exists
check_volume_exists() {
    local volume_name="$1"
    docker volume ls --filter "name=${volume_name}" --format "{{.Name}}" | grep -q "${volume_name}"
    return $?
}

# Main test suite
echo -e "${YELLOW}Starting WordPress Swarm Deployment Test Suite${NC}"

# Check if Docker is installed
run_test "Docker is installed" "docker --version"

# Check if Docker Swarm is active
run_test "Docker Swarm is active" "check_swarm_active"

# Check if the stack is deployed
if check_service_running "wordpress_wordpress_nginx"; then
    echo -e "${GREEN}WordPress stack is already deployed${NC}"
else
    echo -e "${YELLOW}Deploying WordPress stack...${NC}"
    docker stack deploy -c docker-stack.yml wordpress
    sleep 30  # Wait for services to start
fi

# Check if secrets exist
run_test "MySQL root password secret exists" "check_secret_exists 'wordpress_mysql_root_password'"
run_test "MySQL password secret exists" "check_secret_exists 'wordpress_mysql_password'"

# Check if networks exist
run_test "Frontend network exists" "check_network_exists 'wordpress_frontend'"
run_test "Backend network exists" "check_network_exists 'wordpress_backend'"

# Check if volumes exist
run_test "WordPress content volume exists" "check_volume_exists 'wordpress_wp-content'"
run_test "MariaDB data volume exists" "check_volume_exists 'wordpress_wpdb-data'"
run_test "Letsencrypt volume exists" "check_volume_exists 'wordpress_letsencrypt'"

# Check if services are running
run_test "Traefik service is running" "check_service_running 'wordpress_traefik'"
run_test "WordPress Nginx service is running" "check_service_running 'wordpress_wordpress_nginx'"
run_test "WordPress FPM service is running" "check_service_running 'wordpress_wordpress_fpm'"
run_test "MariaDB service is running" "check_service_running 'wordpress_wpdbcluster'"
run_test "Redis service is running" "check_service_running 'wordpress_redis'"

# Check if services have the expected number of replicas
run_test "WordPress Nginx has correct replicas" "check_service_replicas 'wordpress_wordpress_nginx' 2"
run_test "WordPress FPM has correct replicas" "check_service_replicas 'wordpress_wordpress_fpm' 2"
run_test "MariaDB has correct replicas" "check_service_replicas 'wordpress_wpdbcluster' 3"
run_test "Redis has correct replicas" "check_service_replicas 'wordpress_redis' 1"

# Check if services are healthy
run_test "WordPress Nginx is healthy" "check_service_health 'wordpress_wordpress_nginx'"
run_test "WordPress FPM is healthy" "check_service_health 'wordpress_wordpress_fpm'"
run_test "MariaDB is healthy" "check_service_health 'wordpress_wpdbcluster'"
run_test "Redis is healthy" "check_service_health 'wordpress_redis'"

# Check if ports are open
run_test "Port 80 is open" "check_port_open 'localhost' 80"
run_test "Port 443 is open" "check_port_open 'localhost' 443"

# Check if WordPress is accessible (replace with your domain)
# run_test "WordPress is accessible" "check_url_status 'http://your-domain.com'"

# Print test summary
echo -e "\n${YELLOW}Test Summary${NC}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}/${TESTS_TOTAL}${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}/${TESTS_TOTAL}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
