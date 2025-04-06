#!/bin/bash
# Unit tests for MariaDB Galera Cluster
# This script tests the MariaDB Galera Cluster configuration and functionality

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

# Function to check if Galera is running
check_galera_running() {
    local container_id=$(get_container_id "wordpress_wpdbcluster")
    exec_in_container ${container_id} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"SHOW STATUS LIKE 'wsrep_cluster_size'\" | grep -q '[1-9]'"
}

# Function to check Galera cluster size
check_galera_cluster_size() {
    local container_id=$(get_container_id "wordpress_wpdbcluster")
    local expected_size="$1"
    local actual_size=$(exec_in_container ${container_id} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"SHOW STATUS LIKE 'wsrep_cluster_size'\" | grep -oP '\d+'")
    
    if [ "$actual_size" -eq "$expected_size" ]; then
        return 0
    else
        echo "Expected cluster size ${expected_size}, but found ${actual_size}"
        return 1
    fi
}

# Function to check if a database exists
check_database_exists() {
    local container_id=$(get_container_id "wordpress_wpdbcluster")
    local database_name="$1"
    exec_in_container ${container_id} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"SHOW DATABASES LIKE '${database_name}'\" | grep -q '${database_name}'"
}

# Function to check if a user exists
check_user_exists() {
    local container_id=$(get_container_id "wordpress_wpdbcluster")
    local user_name="$1"
    local host="${2:-%}"
    exec_in_container ${container_id} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"SELECT User FROM mysql.user WHERE User='${user_name}' AND Host='${host}'\" | grep -q '${user_name}'"
}

# Function to check if replication is working
check_replication() {
    # Get container IDs for all MariaDB nodes
    local container_ids=($(docker ps --filter "name=wordpress_wpdbcluster" --format "{{.ID}}"))
    
    if [ ${#container_ids[@]} -lt 2 ]; then
        echo "Need at least 2 MariaDB nodes to test replication"
        return 1
    fi
    
    # Create a test table on the first node
    exec_in_container ${container_ids[0]} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"CREATE DATABASE IF NOT EXISTS test_replication; USE test_replication; CREATE TABLE IF NOT EXISTS test_table (id INT PRIMARY KEY, value VARCHAR(255)); INSERT INTO test_table VALUES (1, 'test_value_$(date +%s)');\""
    
    # Check if the table exists on the second node
    sleep 2  # Give some time for replication
    exec_in_container ${container_ids[1]} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"USE test_replication; SELECT * FROM test_table WHERE id=1;\" | grep -q 'test_value'"
}

# Main test suite
echo -e "${YELLOW}Starting MariaDB Galera Cluster Tests${NC}"

# Check if the MariaDB service is running
if ! docker service ls --filter "name=wordpress_wpdbcluster" --format "{{.Name}}" | grep -q "wordpress_wpdbcluster"; then
    echo -e "${RED}MariaDB service is not running. Please deploy the stack first.${NC}"
    exit 1
fi

# Wait for MariaDB to be ready
echo -e "${YELLOW}Waiting for MariaDB to be ready...${NC}"
sleep 10

# Basic tests
run_test "Galera is running" "check_galera_running"
run_test "WordPress database exists" "check_database_exists 'wordpress'"
run_test "WordPress user exists" "check_user_exists 'wordpress'"
run_test "Galera user exists" "check_user_exists 'galera_user'"

# Cluster tests
run_test "Galera cluster has correct size" "check_galera_cluster_size 3"

# Replication test
run_test "Replication is working" "check_replication"

# Clean up test database
container_id=$(get_container_id "wordpress_wpdbcluster")
exec_in_container ${container_id} "mysql -u root -p\$(cat /run/secrets/mysql_root_password) -e \"DROP DATABASE IF EXISTS test_replication;\""

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
