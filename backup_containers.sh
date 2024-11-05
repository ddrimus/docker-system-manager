#!/bin/bash

#####################################################################################
# Script Name: backup_containers.sh
# Author: ddrimus
# Repository: https://github.com/ddrimus/docker-system-manager
# Version: 1.0
# Description: Stop Docker containers, create a backup, and restart containers.
#####################################################################################

# Exit when a command fails (use "|| :" after a command to allow it to fail).
set -o errexit

# Initialize global variables
LOG_FILE=""
OWNER_GROUP=""
SOURCE_DIR_BACKUP=""
BACKUP_DIR_TMP=""
BACKUP_DIR_LOCAL=""
SOURCE_BLACKLIST=""
ENABLE_S3_BACKUP=""
BACKUP_S3_ENDPOINT=""
BACKUP_S3_ACCESS_KEY=""
BACKUP_S3_SECRET_KEY=""
BACKUP_S3_BUCKET=""
BACKUP_RETENTION_DAYS=""

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize logging
init_log() {
    LOG_FILE="$PWD/log/backup_containers.log"
    if mkdir -p "$(dirname "$LOG_FILE")"; then
        log_info "Log directory created successfully."
    else
        log_error "Failed to create log directory."
    fi
    if touch "$LOG_FILE" && > "$LOG_FILE"; then
        log_info "Log file created or cleared successfully."
    else
        log_error "Failed to create or clear the log file."
    fi
}

# Logging function
log() {
    local LEVEL=$1
    local MESSAGE=$2
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] [$LEVEL] $MESSAGE" >> "$LOG_FILE"
}

# Convenience functions for different log levels
log_info()  { log INFO "$1"; }
log_warn()  { log WARN "$1"; }
log_error() { log ERROR "$1"; }

# Load environment variables
load_environment() {
    local ENV_FILE="$(dirname "$0")/.env"
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Error: .env file not found at $ENV_FILE"
        echo -e "Error: .env file not found at $ENV_FILE"
        exit 1
    fi
    log_info "Loading environment variables from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
    OWNER_GROUP=$OWNER_GROUP
    SOURCE_DIR_BACKUP=$SOURCE_DIR_BACKUP
    BACKUP_DIR_TMP=$BACKUP_DIR_TMP
    BACKUP_DIR_LOCAL=$BACKUP_DIR_LOCAL
    IFS=',' read -r -a EXCLUDE_ARRAY <<< "$SOURCE_BLACKLIST"
    EXCLUDE_OPTIONS=""
    for ITEM in "${EXCLUDE_ARRAY[@]}"; do
        EXCLUDE_OPTIONS+=" --exclude=$ITEM"
    done
    ENABLE_S3_BACKUP=${ENABLE_S3_BACKUP:-false}
    BACKUP_S3_ENDPOINT=$BACKUP_S3_ENDPOINT
    BACKUP_S3_ACCESS_KEY=$BACKUP_S3_ACCESS_KEY
    BACKUP_S3_SECRET_KEY=$BACKUP_S3_SECRET_KEY
    BACKUP_S3_BUCKET=$BACKUP_S3_BUCKET
    BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS
    log_info "Environment variables loaded successfully"
}

# Function to run tasks with a spinning indicator
run_with_spin() {
    local TASK_NAME="$1"
    shift
    local COMMAND="$*"
    log_info "Starting: $TASK_NAME - $COMMAND"
    eval "$COMMAND" &> /dev/null &
    local PID=$!
    local SP="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local I=0
    while kill -0 $PID 2>/dev/null; do
        printf "\r[${YELLOW}%s${NC}] %s" "${SP:I++%${#SP}:1}" "$TASK_NAME"
        sleep .1
    done
    if wait $PID 2>/dev/null; then
        printf "\r[${GREEN}✓${NC}] %s\n" "$TASK_NAME"
        log_info "Successfully completed: $TASK_NAME"
    else
        printf "\r[${RED}x${NC}] %s\n" "$TASK_NAME"
        log_error "Failed to complete: $TASK_NAME"
    fi
}

# Function to backup docker
backup_containers() {
    local HOSTNAME="$HOSTNAME"
    local SUFFIX="$(date +"%FT%H%M")${1:+_}$(echo "$@" | sed -e 's/[^a-zA-Z0-9]/-/g' -e 's/ /-/g')"
    local ARCHIVE_NAME="${HOSTNAME}_${SUFFIX}.tgz"
    log_info "Function backup_containers started"
    # Stop all docker containers
    log_info "Stopping all Docker containers"
    if run_with_spin "Stopping all docker containers..." "docker stop \$(docker ps -q)"; then
        log_info "All Docker containers stopped successfully."
    else
        log_error "Failed to stop Docker containers."
    fi
    # Create tar archive in temporary folder
    log_info "Creating tar archive in temporary folder"
    if run_with_spin "Creating tar archive..." "cd $SOURCE_DIR_BACKUP && mkdir -p $BACKUP_DIR_TMP && sudo tar -cpzf $BACKUP_DIR_TMP/$ARCHIVE_NAME --warning=no-file-changed $EXCLUDE_OPTIONS *"; then
        log_info "Tar archive created successfully in temporary folder."
    else
        log_error "Failed to create tar archive in temporary folder."
    fi
    # Copy archive from temporary folder to local folder
    log_info "Copying archive from temporary folder to local folder"
    if run_with_spin "Copying to local folder..." "mkdir -p $BACKUP_DIR_LOCAL && cp $BACKUP_DIR_TMP/$ARCHIVE_NAME $BACKUP_DIR_LOCAL/$ARCHIVE_NAME"; then
        log_info "Archive copied to local folder successfully."
        sudo chown -R "$OWNER_GROUP" "$BACKUP_DIR_LOCAL"
    else
        log_error "Failed to copy archive to local folder."
    fi
    # Clean files older than the specified retention days in local folder, if retention is greater than 0
    if [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
        log_info "Cleaning files older than $BACKUP_RETENTION_DAYS days in local folder"
        if run_with_spin "Cleaning old files in local folder..." "find $BACKUP_DIR_LOCAL -type f -mtime +$BACKUP_RETENTION_DAYS -delete"; then
            log_info "Old files cleaned successfully in local folder."
        else
            log_warn "Failed to clean old files in local folder."
        fi
    else
        log_info "Backup retention is set to 0 days, skipping file cleanup."
    fi
    # Upload backup archive to specified bucket if ENABLE_S3_BACKUP is set to true, otherwise skip this step
    if [ "$ENABLE_S3_BACKUP" = "true" ]; then
        log_info "S3 backup is enabled. Starting file upload to S3 bucket $BACKUP_S3_BUCKET..."
        log_info "Uploading file to S3 bucket $BACKUP_S3_BUCKET"
        if run_with_spin "Uploading file to S3 bucket..." "
            curl -X PUT -T \"$BACKUP_DIR_TMP/$ARCHIVE_NAME\" \\
                -H \"Date: \$(date -R)\" \\
                -H \"Content-Type: application/octet-stream\" \\
                -H \"Authorization: AWS $BACKUP_S3_ACCESS_KEY:\$( \\
                    echo -en \"PUT\n\napplication/octet-stream\n\$(date -R)\n/$BACKUP_S3_BUCKET/$ARCHIVE_NAME\" | \\
                    openssl sha1 -hmac \"$BACKUP_S3_SECRET_KEY\" -binary | base64 \\
                )\" \\
                \"$BACKUP_S3_ENDPOINT/$BACKUP_S3_BUCKET/$ARCHIVE_NAME\""; then
            log_info "File uploaded successfully to $BACKUP_S3_BUCKET."
        else
            log_error "File upload failed. Possible issues with bucket accessibility or credentials."
        fi
    else
        log_info "S3 backup is disabled. Skipping file upload."
    fi
    # Clean temporary folder
    log_info "Cleaning temporary folder"
    if run_with_spin "Cleaning temporary folder..." "sudo rm -r $BACKUP_DIR_TMP"; then
        log_info "Temporary folder cleaned successfully."
    else
        log_warn "Failed to clean temporary folder."
    fi
    # Start all docker containers
    log_info "Starting all Docker containers"
    if run_with_spin "Starting all docker containers..." "docker start \$(docker ps -a -q)"; then
        log_info "All Docker containers started successfully."
    else
        log_error "Failed to start Docker containers."
    fi
    log_info "Function backup_containers completed"
}

# Prompt user for confirmation before proceeding
confirm_execution() {
    echo -e -n "Proceeding with the execution of this script: Are you sure? <Y/N> "
    read PROMPT
    if [[ $PROMPT == "y" || $PROMPT == "Y" ]]; then
        log_info "User confirmed script execution"
    else
        log_info "User aborted script execution"
        exit 0
    fi
}

# Check if script is running with root privileges
check_root() {
    if [ "$UID" -ne 0 ]; then
        log_warn "Script not running with root privileges"
        if sudo -n true 2>/dev/null; then
            log_info "Elevating privileges with sudo"
            exec sudo bash "$0" "$@"
        else
            log_warn "Sudo privileges required. Prompting user."
            exec sudo bash "$0" "$@"
        fi
    else
        log_info "Script running with root privileges"
    fi
}

# Main function to execute script tasks
main() {
    log_info "Script execution started"
    backup_containers "$@"
    log_info "Script execution completed"
}

# Start the process
init_log
load_environment
check_root "$@"
confirm_execution "$@"
main "$@"

exit 0