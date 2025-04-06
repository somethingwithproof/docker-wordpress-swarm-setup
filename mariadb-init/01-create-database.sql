-- This script will be executed when the MariaDB container is first initialized
-- It creates the WordPress database and user if they don't already exist

-- Create WordPress database if it doesn't exist
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- For security, we're using secrets for passwords, so we don't hardcode them here
-- The MYSQL_USER and MYSQL_PASSWORD environment variables will be used by the Docker image
-- to create the user automatically

-- Grant privileges to the WordPress user
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'%';

-- Create Galera user for SST/IST if it doesn't exist
-- The password is set via environment variables in the Docker container
CREATE USER IF NOT EXISTS 'galera_user'@'%';
GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'galera_user'@'%';

-- Flush privileges to apply changes
FLUSH PRIVILEGES;
