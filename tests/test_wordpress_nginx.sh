#!/bin/bash
# Unit tests for WordPress and Nginx
# This script tests the WordPress and Nginx configuration and functionality

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

# Function to get a container ID for a service
get_container_id() {
    local service_name="$1"
    docker ps --filter "name=${service_name}" --format "{{.ID}}" | head -1
}

# Function to execute a command in a container
exec_in_container() {
    local container_id="$1"
    local command="$2"
    docker exec ${container_id} bash -c "${command}"
}

# Function to check if Nginx is running
check_nginx_running() {
    local container_id=$(get_container_id "wordpress_wordpress_nginx")
    exec_in_container ${container_id} "nginx -t"
}

# Function to check if PHP-FPM is running
check_php_fpm_running() {
    local container_id=$(get_container_id "wordpress_wordpress_fpm")
    exec_in_container ${container_id} "ps aux | grep -v grep | grep -q 'php-fpm'"
}

# Function to check if WordPress files exist
check_wordpress_files() {
    local container_id=$(get_container_id "wordpress_wordpress_fpm")
    exec_in_container ${container_id} "test -f /var/www/html/wp-config.php && test -f /var/www/html/index.php"
}

# Function to check if WordPress can connect to the database
check_wordpress_db_connection() {
    local container_id=$(get_container_id "wordpress_wordpress_fpm")
    exec_in_container ${container_id} "php -r \"define('DB_HOST', 'wpdbcluster'); define('DB_NAME', 'wordpress'); define('DB_USER', 'wordpress'); define('DB_PASSWORD', file_get_contents('/run/secrets/mysql_password')); \$conn = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME); if (\$conn->connect_error) { exit(1); } echo 'Connected successfully'; exit(0);\""
}

# Function to check if Nginx is configured correctly
check_nginx_config() {
    local container_id=$(get_container_id "wordpress_wordpress_nginx")
    exec_in_container ${container_id} "nginx -T | grep -q 'fastcgi_pass php'"
}

# Function to check if Nginx is serving WordPress
check_nginx_serving_wordpress() {
    local container_id=$(get_container_id "wordpress_wordpress_nginx")
    exec_in_container ${container_id} "curl -s http://localhost/ | grep -q -i 'wordpress'"
}

# Function to check if WordPress is using Redis
check_wordpress_redis() {
    local container_id=$(get_container_id "wordpress_wordpress_fpm")
    exec_in_container ${container_id} "php -r \"if (!extension_loaded('redis')) { exit(1); } \$redis = new Redis(); \$redis->connect('redis', 6379); echo \$redis->ping(); exit(0);\""
}

# Function to check if Traefik is routing to WordPress
check_traefik_routing() {
    # This test requires the domain to be set up correctly
    # For local testing, you can add an entry to /etc/hosts
    local domain="${1:-your-domain.com}"
    curl -s -H "Host: ${domain}" http://localhost/ | grep -q -i 'wordpress'
}

# Function to check if WordPress is secure
check_wordpress_security() {
    local container_id=$(get_container_id "wordpress_wordpress_nginx")
    
    # Check if wp-config.php is accessible
    local wp_config_accessible=$(exec_in_container ${container_id} "curl -s -o /dev/null -w '%{http_code}' http://localhost/wp-config.php")
    if [ "$wp_config_accessible" -eq 200 ]; then
        echo "wp-config.php is accessible, which is a security risk"
        return 1
    fi
    
    # Check if .git directory is accessible (if it exists)
    local git_accessible=$(exec_in_container ${container_id} "curl -s -o /dev/null -w '%{http_code}' http://localhost/.git/")
    if [ "$git_accessible" -eq 200 ]; then
        echo ".git directory is accessible, which is a security risk"
        return 1
    fi
    
    return 0
}

# Main test suite
echo -e "${YELLOW}Starting WordPress and Nginx Tests${NC}"

# Check if the WordPress and Nginx services are running
if ! docker service ls --filter "name=wordpress_wordpress_nginx" --format "{{.Name}}" | grep -q "wordpress_wordpress_nginx"; then
    echo -e "${RED}WordPress Nginx service is not running. Please deploy the stack first.${NC}"
    exit 1
fi

if ! docker service ls --filter "name=wordpress_wordpress_fpm" --format "{{.Name}}" | grep -q "wordpress_wordpress_fpm"; then
    echo -e "${RED}WordPress FPM service is not running. Please deploy the stack first.${NC}"
    exit 1
fi

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 10

# Basic tests
run_test "Nginx is running" "check_nginx_running"
run_test "PHP-FPM is running" "check_php_fpm_running"
run_test "WordPress files exist" "check_wordpress_files"

# Configuration tests
run_test "Nginx is configured correctly" "check_nginx_config"
run_test "WordPress can connect to the database" "check_wordpress_db_connection"

# Functionality tests
run_test "Nginx is serving WordPress" "check_nginx_serving_wordpress"
run_test "WordPress is using Redis" "check_wordpress_redis"

# Security tests
run_test "WordPress is secure" "check_wordpress_security"

# Traefik routing test (uncomment and modify for your domain)
# run_test "Traefik is routing to WordPress" "check_traefik_routing 'your-domain.com'"

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
