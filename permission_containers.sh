#!/bin/bash

#####################################################################################
# Script Name: permission_containers.sh
# Author: ddrimus
# Repository: https://github.com/ddrimus/docker-system-manager
# Version: 1.0
# Description: Set appropriate permissions for Docker containers.
#####################################################################################

# Exit when a command fails (use "|| :" after a command to allow it to fail).
set -o errexit

# Initialize global variables
LOG_FILE=""

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize logging
init_log() {
    LOG_FILE="$PWD/log/permission_containers.log"
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

# Function to configure permissions for traefik container
permission_traefik() {
    log_info "Function permission_traefik started"
    if [[ ! "$(docker ps -a -q -f name=traefik)" ]]; then
        log_info "Adding permission to traefik container (acme.json)..."
        run_with_spin "Updating permission of traefik acme.json..." "sudo chmod 600 /srv/docker/containers/traefik/data/traefik/ssl/acme.json"
    else
        log_error "Traefik container is running. Permission change skipped."
        echo -ne "Traefik container is running. Permission change skipped.\n"
    fi
    log_info "Function permission_traefik completed"
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
    permission_traefik
    log_info "Script execution completed"
}

# Start the process
init_log
check_root
confirm_execution
main

exit 0