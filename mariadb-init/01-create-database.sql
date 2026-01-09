-- =============================================================================
-- MariaDB Initialization Script for WordPress Galera Cluster
-- This script is idempotent and follows the principle of least privilege
-- =============================================================================

-- Create WordPress database if it doesn't exist
CREATE DATABASE IF NOT EXISTS wordpress
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- =============================================================================
-- WordPress Application User (Least Privilege)
-- =============================================================================
-- Create WordPress user if not exists (password set via MYSQL_PASSWORD env var)
-- The Docker image creates this user automatically, but we ensure it exists
CREATE USER IF NOT EXISTS 'wordpress'@'%';

-- Grant only the permissions WordPress actually needs:
-- SELECT, INSERT, UPDATE, DELETE - Basic CRUD operations
-- CREATE, DROP, ALTER - For plugin/theme installations and updates
-- INDEX - For performance optimization by plugins
-- CREATE TEMPORARY TABLES - Required by some plugins for complex queries
-- LOCK TABLES - Required for wp-cli and some backup plugins
-- REFERENCES - Required for foreign key constraints (some plugins)
GRANT SELECT, INSERT, UPDATE, DELETE,
      CREATE, DROP, ALTER, INDEX,
      CREATE TEMPORARY TABLES, LOCK TABLES, REFERENCES
    ON wordpress.*
    TO 'wordpress'@'%';

-- Note: WordPress does NOT need these dangerous permissions:
-- FILE, PROCESS, SUPER, SHUTDOWN, RELOAD, GRANT OPTION
-- EVENT, TRIGGER (unless specific plugins require them)

-- =============================================================================
-- Galera Cluster SST/IST User
-- =============================================================================
-- Create Galera replication user if not exists
CREATE USER IF NOT EXISTS 'galera_user'@'localhost';
CREATE USER IF NOT EXISTS 'galera_user'@'%';

-- Galera SST requires these specific permissions for State Snapshot Transfer:
-- RELOAD - Required for FLUSH operations during SST
-- PROCESS - Required to view running processes
-- LOCK TABLES - Required during SST to ensure consistency
-- REPLICATION CLIENT - Required for replication status monitoring
GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT
    ON *.*
    TO 'galera_user'@'localhost';

GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT
    ON *.*
    TO 'galera_user'@'%';

-- =============================================================================
-- Health Check User (Optional - for external monitoring)
-- =============================================================================
CREATE USER IF NOT EXISTS 'healthcheck'@'localhost' IDENTIFIED BY 'healthcheck';

-- Minimal permissions for health checks
GRANT SELECT ON mysql.user TO 'healthcheck'@'localhost';
GRANT PROCESS ON *.* TO 'healthcheck'@'localhost';

-- =============================================================================
-- Apply all privilege changes
-- =============================================================================
FLUSH PRIVILEGES;

-- Verification queries (logged during initialization)
SELECT 'Database initialization completed successfully' AS status;
SELECT User, Host FROM mysql.user WHERE User IN ('wordpress', 'galera_user', 'healthcheck');
