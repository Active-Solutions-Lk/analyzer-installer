#!/bin/bash

# Configuration
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/Active-Solutions-Lk/synalyzer-client-be-v2.git"
INSTALL_DIR="$(pwd)/synalyzer"
DB_NAME="synalyzer"
DB_USER="admin"
DB_PASS="Admin@1234"

# Functions
# -----------------------------------------------------------------------------
print_header() {
    echo -e "\n\033[1;34m==========================================\033[0m"
    echo -e "\033[1;34m$1\033[0m"
    echo -e "\033[1;34m==========================================\033[0m"
}

print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m✗ ERROR: $1\033[0m"
    exit 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
    fi
}

# 1. System Requirements & Dependencies
# -----------------------------------------------------------------------------
check_root

print_header "1. Installing System Dependencies..."

if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update -qq
    apt-get install -y git mariadb-server php-cli php-mysql php-curl cron bc net-tools &> /dev/null
elif command -v yum &> /dev/null; then
    # RHEL/CentOS
    yum install -y git mariadb-server php-cli php-mysql php-curl cronie bc net-tools &> /dev/null
    systemctl enable --now mariadb
    systemctl enable --now crond
else
    print_error "Unsupported package manager. Please install dependencies manually."
fi

print_success "Dependencies installed."

# 2. Clone Repository
# -----------------------------------------------------------------------------
print_header "2. Cloning Repository..."

if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists. Pulling latest changes..."
    cd "$INSTALL_DIR" && git pull
else
    echo "Cloning into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    
    # Handle optional auth if public clone fails (using the logic you provided earlier)
    if [ $? -ne 0 ]; then
        echo ""
        echo "Authentication required for private repository."
        read -rp "GitHub Username: " GIT_USER
        read -rsp "GitHub Password / Token: " GIT_PASS
        echo ""
        ENCODED_URL="https://${GIT_USER}:${GIT_PASS}@github.com/${REPO_URL#https://github.com/}"
        git clone "$ENCODED_URL" "$INSTALL_DIR" || print_error "Failed to clone repository."
    fi
fi

print_success "Repository setup complete."

# 3. Database Configuration
# -----------------------------------------------------------------------------
print_header "3. Configuring Database..."

# Start MariaDB if not running
systemctl start mariadb

# Create DB and User
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Import Schema
SCHEMA_FILE="$INSTALL_DIR/client_side/database/synalyzer.sql"
if [ -f "$SCHEMA_FILE" ]; then
    mysql "$DB_NAME" < "$SCHEMA_FILE"
    print_success "Database schema imported."
else
    print_error "Schema file not found at $SCHEMA_FILE"
fi

# 4. Inject Configuration
# -----------------------------------------------------------------------------
print_header "4. Updating Configuration Files..."

# Update Config.php
CONFIG_FILE="$INSTALL_DIR/client_side/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
    sed -i "s/'database' => '.*'/'database' => '$DB_NAME'/" "$CONFIG_FILE"
    sed -i "s/'username' => '.*'/'username' => '$DB_USER'/" "$CONFIG_FILE"
    sed -i "s/'password' => '.*'/'password' => '$DB_PASS'/" "$CONFIG_FILE"
    print_success "Updated config.php with DB credentials."
else
    echo "Warning: config.php not found."
fi

# Update Fetch Script
FETCH_SCRIPT="$INSTALL_DIR/client_side/backend/fetch_collector_logs.sh"
if [ -f "$FETCH_SCRIPT" ]; then
    sed -i 's/LOCAL_USER=".*"/LOCAL_USER="'"$DB_USER"'"/' "$FETCH_SCRIPT"
    sed -i 's/LOCAL_PASS=".*"/LOCAL_PASS="'"$DB_PASS"'"/' "$FETCH_SCRIPT"
    sed -i 's/LOCAL_DB=".*"/LOCAL_DB="'"$DB_NAME"'"/' "$FETCH_SCRIPT"
    chmod +x "$FETCH_SCRIPT"
    print_success "Updated fetch_collector_logs.sh with DB credentials."
else
    echo "Warning: fetch_collector_logs.sh not found."
fi

# Update Agent Script (Assuming standard location)
AGENT_SCRIPT="$INSTALL_DIR/client_side/scripts/run_agent.sh"
if [ -f "$AGENT_SCRIPT" ]; then
    chmod +x "$AGENT_SCRIPT"
fi

# 5. Setup Cron Jobs
# -----------------------------------------------------------------------------
print_header "5. Installing Cron Jobs..."

# Remove existing jobs for this specific directory to avoid duplicates
(crontab -l 2>/dev/null | grep -v "$INSTALL_DIR") | crontab -

# Add new jobs
CRON_JOB_1="* * * * * $FETCH_SCRIPT >> $INSTALL_DIR/logs/fetch.log 2>&1"
CRON_JOB_2="*/5 * * * * $AGENT_SCRIPT >> $INSTALL_DIR/logs/agent.log 2>&1"

# Create logs directory
mkdir -p "$INSTALL_DIR/logs"

(crontab -l 2>/dev/null; echo "$CRON_JOB_1"; echo "$CRON_JOB_2") | crontab -

print_success "Cron jobs installed:"
echo "   - Every 1 min: Fetch Collector Logs"
echo "   - Every 5 min: Health Agent Check"

# 6. Final Summary
# -----------------------------------------------------------------------------
print_header "Installation Complete!"
echo "Installation Directory: $INSTALL_DIR"
echo "Database: $DB_NAME (User: $DB_USER)"
echo "Logs: $INSTALL_DIR/logs/"
echo ""
echo "Note: Ensure 'config.php' has the correct Central Server URL if not hardcoded in repo."