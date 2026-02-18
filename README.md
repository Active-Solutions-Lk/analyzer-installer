# Synalyzer Client Deployment Guide

This document explains how to deploy the Synalyzer Client (Analyzer) on a Linux VPS using the automated installer script.

## 1. Prerequisites

*   **Operating System**: Linux (CentOS 7/8, RHEL, Ubuntu 20.04+, Debian 10+)
*   **Access**: Root privileges (`sudo`)
*   **Network**: Internet access to clone the repository and install packages.
*   **GitHub Credentials**: If the repository is private, you will need a GitHub username and Personal Access Token (PAT).

## 2. Quick Start

Run the following commands on your client machine:

```bash
# 1. Download the installer (if not already present)
# You can scp it from your local machine or create it manually:
nano install_analyzer.sh
# (Paste the contents of install_analyzer.sh)

# 2. Make it executable
chmod +x install_analyzer.sh

# 3. Run the installer
sudo ./install_analyzer.sh
```

## 3. What the Script Does

The `install_analyzer.sh` script automates the entire setup process:

1.  **System Preparation**:
    *   Detects the OS (Debian/Ubuntu vs. RHEL/CentOS).
    *   Installs required dependencies: `git`, `mariadb-server`, `php` (CLI, MySQL, Curl), `cron`, `bc`, `net-tools`.

2.  **Repository Setup**:
    *   Clones the `synalyzer-client-be-v2` repository into a `synalyzer` subdirectory.
    *   Prompts for GitHub credentials if public access fails.

3.  **Database Configuration**:
    *   Starts the MariaDB service.
    *   Creates the `synalyzer` database.
    *   Creates a dedicated database user (`admin` / `Admin@1234`).
    *   Imports the database schema from `client_side/database/synalyzer.sql`.

4.  **Application Configuration**:
    *   Updates `client_side/config/config.php` with the new database credentials.
    *   Updates `client_side/backend/fetch_collector_logs.sh` with the new database credentials.
    *   Sets executable permissions for all backend scripts.

5.  **Automation (Cron Jobs)**:
    *   **Every 1 Minute**: Runs `fetch_collector_logs.sh` to sync logs from collectors.
    *   **Every 5 Minutes**: Runs `run_agent.sh` to report health status to the central server.
    *   Logs are stored in `synalyzer/logs/`.

## 4. Troubleshooting

### Permission Denied (Git Clone)
If the script fails to clone the repository:
*   Ensure you are using a **Personal Access Token (PAT)** instead of a password, as GitHub no longer supports password authentication for Git over HTTPS.

### Database Connection Error
If the scripts cannot connect to the database:
*   Check if MariaDB is running: `systemctl status mariadb`
*   Verify credentials in `client_side/config/config.php`.

### Logs Not Fetching
*   Check the log file: `tail -f synalyzer/logs/fetch.log`
*   Ensure the Collector IP is reachable from the client machine.
