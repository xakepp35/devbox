#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RESET="$(tput sgr0)"
BOLD="$(tput bold)"

RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"


print_stage() {
  echo -e "\n${BLUE}🔹 ${BOLD}$1${RESET}"
}

print_success() {
  echo -e "${GREEN}✅ $1${RESET}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${RESET}"
}

# -----------------------------------------------------------------------------
# Stage 1: Prepare working directory
# -----------------------------------------------------------------------------
print_stage "Stage 1: Preparing working directory"

[ -d "gitlab" ] && rm -rf gitlab
mkdir -p gitlab
cd gitlab || exit 1

print_success "Working directory 'gitlab' is ready."

# -----------------------------------------------------------------------------
# Stage 2: Generate random passwords
# -----------------------------------------------------------------------------
print_stage "Stage 2: Generating credentials"

generate_password() {
  local length=${1:-12}
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
  echo
}

GITLAB_HOST="git.dev.box"
GITLAB_EXTERNAL_URL="http://git.dev.box"

GITLAB_ROOT_EMAIL="root@anykey.pro"
GITLAB_ROOT_PASSWORD="$(generate_password 13)"

GITLAB_POSTGRES_USER="gitlab"
GITLAB_POSTGRES_PASSWORD="$(generate_password 13)"
GITLAB_POSTGRES_DB="gitlabhq_production"

GITLAB_REDIS_PASSWORD="$(generate_password 13)"

print_success "Passwords generated successfully."

# -----------------------------------------------------------------------------
# Stage 3: Generate .env file
# -----------------------------------------------------------------------------
print_stage "Stage 3: Creating .env file"

ENV_FILE=".env"
rm -f "$ENV_FILE"

cat <<EOL > "$ENV_FILE"
TZ=UTC

GITLAB_HOST=$GITLAB_HOST
GITLAB_EXTERNAL_URL=$GITLAB_EXTERNAL_URL

GITLAB_ROOT_EMAIL=$GITLAB_ROOT_EMAIL
GITLAB_ROOT_PASSWORD=$GITLAB_ROOT_PASSWORD

GITLAB_POSTGRES_USER=$GITLAB_POSTGRES_USER
GITLAB_POSTGRES_PASSWORD=$GITLAB_POSTGRES_PASSWORD
GITLAB_POSTGRES_DB=$GITLAB_POSTGRES_DB

GITLAB_REDIS_PASSWORD=$GITLAB_REDIS_PASSWORD
EOL

print_success ".env file created."

# -----------------------------------------------------------------------------
# Stage 4: Generate config.rb file
# -----------------------------------------------------------------------------
print_stage "Stage 4: Creating config.rb file"

CONFIG_GITLAB_FILE="config.rb"
rm -f "$CONFIG_GITLAB_FILE"

cat <<EOL > "$CONFIG_GITLAB_FILE"
external_url ENV['GITLAB_EXTERNAL_URL']

gitlab_rails['initial_root_email'] = ENV['GITLAB_ROOT_EMAIL']
gitlab_rails['initial_root_password'] = ENV['GITLAB_ROOT_PASSWORD']

postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_database'] = ENV['GITLAB_POSTGRES_DB']
gitlab_rails['db_username'] = ENV['GITLAB_POSTGRES_USER']
gitlab_rails['db_password'] = ENV['GITLAB_POSTGRES_PASSWORD']
gitlab_rails['db_host'] = 'gitlab-postgres'
gitlab_rails['db_port'] = 5432

gitlab_rails['redis_host'] = 'gitlab-redis'
gitlab_rails['redis_port'] = 6379
gitlab_rails['redis_password'] = ENV['GITLAB_REDIS_PASSWORD']
gitlab_rails['redis_url'] = "redis://:\#{ENV['GITLAB_REDIS_PASSWORD']}@gitlab-redis:6379/0"
EOL

print_success "config.rb file created."

# -----------------------------------------------------------------------------
# Stage 5: Generate docker-compose.yml
# -----------------------------------------------------------------------------
print_stage "Stage 5: Creating docker-compose.yml"

DOCKER_COMPOSE_FILE="docker-compose.yml"
rm -f "$DOCKER_COMPOSE_FILE"

cat <<EOL > "$DOCKER_COMPOSE_FILE"
version: '3.8'

services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: always
    hostname: $GITLAB_HOST
    ports:
      - "80:80"
      - "443:443"
      - "22:22"
    volumes:
      - "./$CONFIG_GITLAB_FILE:/etc/gitlab/gitlab.rb:ro"
      - "gitlab-data:/var/opt/gitlab"
      - "gitlab-logs:/var/log/gitlab"
      - "gitlab-config:/etc/gitlab"
    env_file:
      - "$ENV_FILE"
    depends_on:
      - gitlab-postgres
      - gitlab-redis

  gitlab-postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: $GITLAB_POSTGRES_DB
      POSTGRES_USER: $GITLAB_POSTGRES_USER
      POSTGRES_PASSWORD: $GITLAB_POSTGRES_PASSWORD
    volumes:
      - "postgres-data:/var/lib/postgresql/data"

  gitlab-redis:
    image: redis:7
    command: [ "redis-server", "--requirepass", "$GITLAB_REDIS_PASSWORD" ]
    volumes:
      - "redis-data:/data"

volumes:
  gitlab-data:
  gitlab-logs:
  gitlab-config:
  postgres-data:
  redis-data:
EOL

print_success "docker-compose.yml file created."

# -----------------------------------------------------------------------------
# Stage 6: Start GitLab stack
# -----------------------------------------------------------------------------
print_stage "Stage 6: Starting GitLab with Docker Compose"

docker compose up -d

print_success "GitLab stack started."

# -----------------------------------------------------------------------------
# Stage 7: Show credentials
# -----------------------------------------------------------------------------
print_stage "Stage 7: GitLab credentials"

echo -e "${YELLOW}🔑 Root Email: ${RESET}${BOLD}$GITLAB_ROOT_EMAIL${RESET}"
echo -e "${YELLOW}🔑 Root Password: ${RESET}${BOLD}$GITLAB_ROOT_PASSWORD${RESET}"
