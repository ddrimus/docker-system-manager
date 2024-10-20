#!/bin/bash

#####################################################################################
# Script Name: restart_containers.sh
# Author: ddrimus
# Repository: https://github.com/ddrimus/docker-system-manager
# Version: 1.0
# Description: Restart Docker containers in a specific folder, no underscores.
#####################################################################################

# Exit when a command fails (use "|| :" after a command to allow it to fail).
set -o errexit

# Initialize global variables
LOG_FILE=""
HIGH_PRIORITY_CONTAINERS=""
STANDARD_PRIORITY_CONTAINERS=""
REMOVE_IMAGES=""

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize logging
init_log() {
    LOG_FILE="$PWD/log/restart_containers.log"
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
    IFS=',' read -r -a HIGH_PRIORITY_CONTAINERS <<< "$HIGH_PRIORITY_CONTAINERS"
    IFS=',' read -r -a STANDARD_PRIORITY_CONTAINERS <<< "$STANDARD_PRIORITY_CONTAINERS"
    REMOVE_IMAGES=${REMOVE_IMAGES:-false}
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

# Function to cleanup docker resources
cleanup_docker() {
    log_info "Function cleanup_docker started"
    # Stop all docker containers
    log_info "Stopping all docker containers..."
    run_with_spin "Stopping all docker containers..." "docker kill \$(docker ps -q)" || log_error "Failed to stop all docker containers"
    # Remove all docker containers
    log_info "Removing all docker containers..."
    run_with_spin "Removing all docker containers..." "docker rm \$(docker ps -a -q)" || log_error "Failed to remove all docker containers"
    # Remove all docker containers images if REMOVE_IMAGES is true
    if [[ "$REMOVE_IMAGES" == "true" ]]; then
        log_info "Removing all docker images..."
        run_with_spin "Removing all docker images..." "docker rmi \$(docker images -q)" || log_error "Failed to remove all docker images"
    else
        log_info "Removing all dangling images..."
        run_with_spin "Removing dangling images..." "docker image prune -f" || log_error "Failed to remove all dangling images"
    fi
    # Remove all docker volumes
    log_info "Removing all docker volumes..."
    run_with_spin "Removing all docker volumes..." "docker volume rm \$(docker volume ls -q)" || log_error "Failed to remove all docker volumes"
    # Remove all docker networks
    log_info "Removing all docker networks..."
    run_with_spin "Removing all docker networks..." "docker network prune -f" || log_error "Failed to remove all docker networks"
    # Remove all docker build cache
    log_info "Removing all docker build cache..."
    run_with_spin "Removing all docker build cache..." "docker builder prune -f" || log_error "Failed to remove all docker build cache"
    log_info "Function cleanup_docker completed"
}

# Function to start high priority containers
run_high_priority() {
    if [ ${#HIGH_PRIORITY_CONTAINERS[@]} -gt 0 ]; then
        log_info "Starting high-priority containers"
        for DIR in "${HIGH_PRIORITY_CONTAINERS[@]}"; do
            local CONTAINER_NAME=$(basename "$DIR")
            if [[ ! "$CONTAINER_NAME" =~ ^_ ]]; then
                log_info "Preparing to start high-priority container: $CONTAINER_NAME"
                run_with_spin "Starting $CONTAINER_NAME (high priority)..." \
                    "cd \"$DIR\" && docker compose up -d"
            else
                log_info "Skipping high-priority container: $CONTAINER_NAME (starts with underscore)"
            fi
        done
    else
        log_warn "No high-priority containers defined, skipping high-priority phase"
    fi
}

# Function to start standard priority containers
run_standard_priority() {
    declare -A HIGH_PRIORITY_MAP
    for DIR in "${HIGH_PRIORITY_CONTAINERS[@]}"; do
        HIGH_PRIORITY_MAP["$DIR"]=1
    done
    log_info "Starting standard-priority containers"
    log_info "STANDARD_PRIORITY_CONTAINERS: $STANDARD_PRIORITY_CONTAINERS"
    EXPANDED_CONTAINERS=($STANDARD_PRIORITY_CONTAINERS)
    for DIR in "${EXPANDED_CONTAINERS[@]}"; do
        log_info "Checking directory: $DIR"
        if [ -d "$DIR" ] && [[ -z "${HIGH_PRIORITY_MAP["$DIR"]}" ]]; then
            local CONTAINER_NAME=$(basename "$DIR")
            if [[ ! "$CONTAINER_NAME" =~ ^_ ]]; then
                log_info "Preparing to start standard-priority container: $CONTAINER_NAME"
                run_with_spin "Starting $CONTAINER_NAME (standard priority)..." \
                    "cd \"$DIR\" && docker compose up -d"
            else
                log_info "Skipping standard-priority container: $CONTAINER_NAME (starts with underscore)"
            fi
        else
            log_info "Skipping $DIR (not a directory or already started as high-priority)"
        fi
    done
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

# Main function to execute script tasks
main() {
    log_info "Script execution started"
    cleanup_docker
    run_high_priority
    run_standard_priority
    log_info "Script execution completed"
}

# Start the process
init_log
load_environment
confirm_execution
main

exit 0