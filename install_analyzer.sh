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
    echo "Updating system repositories..."
    apt-get update || print_error "apt-get update failed."
    
    echo "Installing required packages..."
    # Attempting to install mariadb-server, falling back to mysql-server if needed
    apt-get install -y git mariadb-server php-cli php-mysql php-curl cron bc net-tools || \
    apt-get install -y git mysql-server php-cli php-mysql php-curl cron bc net-tools || \
    print_error "Failed to install dependencies."
    
elif command -v yum &> /dev/null; then
    # RHEL/CentOS
    yum install -y git mariadb-server php-cli php-mysql php-curl cronie bc net-tools || print_error "Failed to install dependencies."
    systemctl enable --now mariadb || systemctl enable --now mysql
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
    cd "$INSTALL_DIR" && git pull || print_error "Failed to pull changes."
else
    echo "Cloning into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    
    # Handle optional auth if public clone fails
    if [ $? -ne 0 ]; then
        echo ""
        echo "Authentication required for private repository."
        read -rp "GitHub Username: " GIT_USER
        read -rsp "GitHub Password / Token: " GIT_PASS
        echo ""
        # Extract repo path from URL
        REPO_PATH=$(echo "$REPO_URL" | sed 's|https://github.com/||')
        ENCODED_URL="https://${GIT_USER}:${GIT_PASS}@github.com/${REPO_PATH}"
        git clone "$ENCODED_URL" "$INSTALL_DIR" || print_error "Failed to clone repository."
    fi
fi

print_success "Repository setup complete."

# 3. Database Configuration
# -----------------------------------------------------------------------------
print_header "3. Configuring Database..."

# Try to start mariadb or mysql
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null

if ! command -v mysql &> /dev/null; then
    print_error "MySQL/MariaDB client is not installed correctly."
fi

# Create DB and User
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Import Schema
# Check multiple possible paths for the schema file
SCHEMA_FILE="$INSTALL_DIR/client_side/database/synalyzer.sql"
if [ ! -f "$SCHEMA_FILE" ]; then
    SCHEMA_FILE=$(find "$INSTALL_DIR" -name "synalyzer.sql" | head -n 1)
fi

if [ -f "$SCHEMA_FILE" ]; then
    echo "Importing schema from $SCHEMA_FILE..."
    mysql "$DB_NAME" < "$SCHEMA_FILE"
    print_success "Database schema imported."
else
    print_error "Schema file (synalyzer.sql) not found in cloned repository."
fi

# 4. Inject Configuration
# -----------------------------------------------------------------------------
print_header "4. Updating Configuration Files..."

# Update Config.php
CONFIG_FILE=$(find "$INSTALL_DIR" -name "config.php" | head -n 1)
if [ -f "$CONFIG_FILE" ]; then
    sed -i "s/'database' => '.*'/'database' => '$DB_NAME'/" "$CONFIG_FILE"
    sed -i "s/'username' => '.*'/'username' => '$DB_USER'/" "$CONFIG_FILE"
    sed -i "s/'password' => '.*'/'password' => '$DB_PASS'/" "$CONFIG_FILE"
    print_success "Updated config.php ($CONFIG_FILE)"
else
    echo "Warning: config.php not found."
fi

# Update Fetch Script
FETCH_SCRIPT=$(find "$INSTALL_DIR" -name "fetch_collector_logs.sh" | head -n 1)
if [ -f "$FETCH_SCRIPT" ]; then
    sed -i 's/LOCAL_USER=".*"/LOCAL_USER="'"$DB_USER"'"/' "$FETCH_SCRIPT"
    sed -i 's/LOCAL_PASS=".*"/LOCAL_PASS="'"$DB_PASS"'"/' "$FETCH_SCRIPT"
    sed -i 's/LOCAL_DB=".*"/LOCAL_DB="'"$DB_NAME"'"/' "$FETCH_SCRIPT"
    chmod +x "$FETCH_SCRIPT"
    print_success "Updated fetch_collector_logs.sh ($FETCH_SCRIPT)"
else
    echo "Warning: fetch_collector_logs.sh not found."
fi

# Update Agent Script
AGENT_SCRIPT=$(find "$INSTALL_DIR" -name "run_agent.sh" | head -n 1)
if [ -f "$AGENT_SCRIPT" ]; then
    chmod +x "$AGENT_SCRIPT"
    print_success "Set executable permission for $AGENT_SCRIPT"
fi

# 5. Setup Cron Jobs
# -----------------------------------------------------------------------------
print_header "5. Installing Cron Jobs..."

# Remove existing jobs for this specific directory to avoid duplicates
(crontab -l 2>/dev/null | grep -v "$INSTALL_DIR") | crontab -

# Add new jobs
if [ -f "$FETCH_SCRIPT" ] && [ -f "$AGENT_SCRIPT" ]; then
    CRON_JOB_1="* * * * * $FETCH_SCRIPT >> $INSTALL_DIR/logs/fetch.log 2>&1"
    CRON_JOB_2="*/5 * * * * $AGENT_SCRIPT >> $INSTALL_DIR/logs/agent.log 2>&1"

    # Create logs directory
    mkdir -p "$INSTALL_DIR/logs"

    (crontab -l 2>/dev/null; echo "$CRON_JOB_1"; echo "$CRON_JOB_2") | crontab -
    print_success "Cron jobs installed."
else
    echo "Warning: Scripts not found, skipping cron job setup."
fi

# 6. Final Summary
# -----------------------------------------------------------------------------
print_header "Installation Complete!"
echo "Installation Directory: $INSTALL_DIR"
echo "Database: $DB_NAME (User: $DB_USER)"
echo "Logs: $INSTALL_DIR/logs/"
echo ""
echo "Note: If there were errors above, please check the output for package installation issues."