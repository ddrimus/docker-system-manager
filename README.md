# Docker System Manager

This collection of Bash scripts is designed to streamline Docker container management. Whether you're restarting or stopping containers, adjusting permissions, or performing backups, these scripts automate routine tasks, reducing the need for manual repetition.

## Scripts

1. **backup_containers.sh**: Stops containers, creates backups, and restarts them afterward.
2. **permission_containers.sh**: Sets up the right permissions for certain containers (like traefik).
3. **restart_containers.sh**: Restarts your containers, handling high and standard priority containers separately.
4. **start_containers.sh**: Starts Docker containers, prioritizing high-priority ones.
5. **stop_containers.sh**: Stops Docker containers and cleans up everything (containers, images, volumes, and networks).

## Getting Started

### Prerequisites

- Docker installed on your machine.
- Root or sudo access to execute the scripts.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ddrimus/docker-system-manager.git
   cd docker-system-manager
   ```

2. Set up the environment file:
   - Copy the example environment file:
     ```bash
     cp example.env .env
     ```
   - Open and edit the `.env` file with your preferred settings:
     ```bash
     nano .env
     ```
   - Save your changes and exit Nano:
     - Press `CTRL + O` to save.
     - Press `CTRL + X` to exit.

3. Make the scripts executable:
   ```bash
   chmod +x *.sh
   ```

## Usage

### backup_containers.sh

The `backup_containers.sh` script is designed to create consistent backups of your Docker containers. It temporarily halts the containers to avoid inconsistencies during the backup process, ensuring a reliable snapshot is created. Once the backup is complete, all containers are restarted. Supports optional S3-compatible remote storage for backups.

#### Configuration

You'll need to configure a few environment variables in the `.env` file:

- `OWNER_GROUP`: Specifies the user and group that should own the backup files.
- `SOURCE_DIR_BACKUP`: The directory that contains the Docker containers to be backed up.
- `BACKUP_DIR_TMP`: A temporary directory used for storing backups during the backup process.
- `BACKUP_DIR_LOCAL`: The destination where finalized backups will be stored.
- `SOURCE_BLACKLIST`: Directories or files to exclude from the backup process.
- `ENABLE_S3_BACKUP`: Toggles the S3 backup functionality. Set to "true" to enable or "false" to disable.
- `BACKUP_S3_ENDPOINT`: URL of the S3-compatible endpoint, specifying the protocol, IP, and port. Example: `http://127.0.0.1:80`
- `BACKUP_S3_ACCESS_KEY`: Access key for authenticating to the S3 endpoint. Ensure this key has the necessary permissions for backup operations.
- `BACKUP_S3_SECRET_KEY`: Secret key for authenticating to the S3 endpoint. Keep this key secure and restrict access.
- `BACKUP_S3_BUCKET`: The name of the S3 bucket where backups will be stored. Ensure this bucket exists and has appropriate permissions.
- `BACKUP_RETENTION_DAYS`: The number of days to retain old backups. Set to `0` to retain all backups indefinitely.

### permission_containers.sh

The `permission_containers.sh` script manages file permissions for Docker containers, focusing on Traefik's `acme.json` by default. It checks if Traefik is running and adjusts permissions when it's not. You can modify the script to handle other containers by adapting the logic to fit your requirements.

#### Configuration

No configuration of environment variables in a `.env` file is required.

### restart_containers.sh

The `restart_containers.sh` script manages Docker container restarts by priority. It stops all containers, cleans up the system by removing containers, images (optional), dangling images, volumes, networks, and build cache, then restarts high-priority containers first, followed by standard ones.

#### Configuration

You'll need to configure a few environment variables in the `.env` file:

- `REMOVE_IMAGES`: If true, Docker images will also be removed.
- `HIGH_PRIORITY_CONTAINERS`: List of containers to start first.
- `STANDARD_PRIORITY_CONTAINERS`: List of containers to start after high-priority ones.

> **Note**: Containers with names starting with an underscore (`_`) will be stopped by this script but not restarted.

### start_containers.sh

The `start_containers.sh` script starts Docker containers based on priority. It first starts high-priority containers, ensuring critical services are running, and then starts the standard containers. This script is useful when specific services need to be up before others, without performing any cleanup or stopping of containers.

#### Configuration

You'll need to configure a few environment variables in the `.env` file:

- `HIGH_PRIORITY_CONTAINERS`: List of containers to start first.
- `STANDARD_PRIORITY_CONTAINERS`: List of containers to start after high-priority ones.

> **Note**: Containers with names starting with an underscore (`_`) will be stopped by this script but not restarted.

### stop_containers.sh

The `stop_containers.sh` script stops all Docker containers and performs a system cleanup. It removes containers, optional Docker images, dangling images, volumes, networks, and build cache, ensuring a clean environment. 

#### Configuration

You'll need to configure the following environment variable in the .env file:

- `REMOVE_IMAGES`: If true, Docker images will also be removed.

## Contributing

We’d love your help! If you have suggestions for improvements or new scripts, feel free to open a pull request.

## Acknowledgments

- Inspired by the need for streamlined Docker container management.
- Thanks to the open-source community for providing valuable insights and resources.
