#!/bin/bash

mkdir -p gitlab
cd gitlab || exit

# Function to generate a password
generate_password() {
    local length=${1:-12} #default length 12
    LC_ALL=C tr -dc 'A-Za-z0-9!@%^&*()_+-=' < /dev/urandom | head -c "$length"
    echo
}

GITLAB_HOST=git.dev.box
GITLAB_EXTERNAL_URL=http://git.dev.box

GITLAB_ROOT_EMAIL=root@anykey.pro
GITLAB_ROOT_PASSWORD=$(generate_password 13)

GITLAB_POSTGRES_USER=gitlab
GITLAB_POSTGRES_PASSWORD=$(generate_password 13)
GITLAB_POSTGRES_DB=gitlabhq_production

GITLAB_REDIS_PASSWORD="$(generate_password 13)"

# Work with .env file
ENV_FILE=".env"
[ -f "$ENV_FILE" ] && rm "$ENV_FILE"

cat <<EOL > "$ENV_FILE"
# Set TZ to gitlab 
TZ=UTC

# Gilab global vars
GITLAB_HOST="$GITLAB_HOST"
GITLAB_EXTERNAL_URL="$GITLAB_EXTERNAL_URL"

# Gitlab root credentials
GITLAB_ROOT_EMAIL="$GITLAB_ROOT_EMAIL"
GITLAB_ROOT_PASSWORD="$GITLAB_ROOT_PASSWORD"

#Gitlab postgres credentials
GITLAB_POSTGRES_PASSWORD="$GITLAB_POSTGRES_PASSWORD"
GITLAB_POSTGRES_USER="$GITLAB_POSTGRES_USER"
GITLAB_POSTGRES_DB="$GITLAB_POSTGRES_DB"

# Gitlab redis credentials
GITLAB_REDIS_PASSWORD="$GITLAB_REDIS_PASSWORD"

EOL

echo ".env file generated successfully!"

# Work with config.rb file
CONFIG_GITLAB_FILE="config.rb"
[ -f "$CONFIG_GITLAB_FILE" ] && rm "$CONFIG_GITLAB_FILE"

cat <<EOL > "$CONFIG_GITLAB_FILE"
# Set TZ to gitlab 
external_url ENV['GITLAB_EXTERNAL_URL']

gitlab_rails['initial_root_email'] = ENV['GITLAB_ROOT_EMAIL']
gitlab_rails['initial_root_password'] = ENV['GITLAB_ROOT_PASSWORD']

# External Postgres
postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_database'] = ENV['GITLAB_POSTGRES_DB']
gitlab_rails['db_username'] = ENV['GITLAB_POSTGRES_USER']
gitlab_rails['db_password'] = ENV['GITLAB_POSTGRES_PASSWORD']
gitlab_rails['db_host'] = 'gitlab-postgres'
gitlab_rails['db_port'] = 5432

# Redis
gitlab_rails['redis_host'] = 'gitlab-redis'
gitlab_rails['redis_port'] = 6379
gitlab_rails['redis_password'] = ENV['GITLAB_REDIS_PASSWORD']
gitlab_rails['redis_url'] = "redis://:#{ENV['GITLAB_REDIS_PASSWORD']}@gitlab-redis:6379/0"

# S3/MinIO backup
# gitlab_rails['backup_upload_connection'] = {
#   'provider' => 'AWS',
#   'region' => ENV['MINIO_REGION'],
#   'aws_access_key_id' => ENV['MINIO_ROOT_USER'],
#   'aws_secret_access_key' => ENV['MINIO_ROOT_PASSWORD'],
#   'endpoint' => 'http://minio:9000',
#   'force_path_style' => true
# }
# gitlab_rails['backup_upload_remote_directory'] = ENV['MINIO_BUCKET']

EOL

echo "config.rb file generated successfully!"


# Work with docker_compose.yml file
DOCKER_COMPOSE_FILE="docker-compose.yml"
[ -f "$DOCKER_COMPOSE_FILE" ] && rm "$DOCKER_COMPOSE_FILE"

cat <<EOL > "$DOCKER_COMPOSE_FILE"
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: always
    hostname: gitlab.example.com
    ports:
      - "80:80"
      - "443:443"
      - "22:22"
    volumes:
      - './$CONFIG_GITLAB_FILE:/etc/gitlab/gitlab.rb:ro'
      - 'gitlab-data:/var/opt/gitlab'
      - 'gitlab-logs:/var/log/gitlab'
      - 'gitlab-config:/etc/gitlab'
    env_file:
      - "${ENV_FILE}"
    depends_on:
      - gitlab-postgres
      - gitlab-redis

  gitlab-postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: "${GITLAB_POSTGRES_DB}"
      POSTGRES_USER: "${GITLAB_POSTGRES_USER}"
      POSTGRES_PASSWORD: "${GITLAB_POSTGRES_PASSWORD}"
    volumes:
      - 'postgres-data:/var/lib/postgresql/data'

  gitlab-redis:
    image: redis:7
    command: [ "redis-server", "--requirepass", "${GITLAB_REDIS_PASSWORD}" ]
    volumes:
      - 'redis-data:/data'

volumes:
  gitlab-data:
  gitlab-logs:
  gitlab-config:
  postgres-data:
  redis-data:

EOL

echo "docker-compose.yml file generated successfully!"


docker compose up -d