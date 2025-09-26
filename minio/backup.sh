#!/usr/bin/env bash
set -euo pipefail

# This script performs an application-level backup of all buckets in a MinIO server.
# It requires the following environment variables to be set by sourcing a .env file:
#   - MINIO_ACCESS_KEY: The root user for the MinIO server.
#   - MINIO_SECRET_KEY: The root password for the MinIO server.

# ------------- configurable -------------
MINIO_ALIAS="minio_backup_alias"   # An internal alias for mc
BACKUP_DIR="./minio_backups"       # A directory on the host to store the backups
DATE=$(date +%F)
ARCHIVE_FILENAME="minio-${DATE}.tar.gz"
ARCHIVE_FULL_PATH="${BACKUP_DIR}/${ARCHIVE_FILENAME}"
RETENTION_DAYS=7
# ----------------------------------------

source .env

# --- Pre-flight Checks ---
if [ -z "${MINIO_ACCESS_KEY-}" ] || [ -z "${MINIO_SECRET_KEY-}" ]; then
  echo "Error: MINIO_ACCESS_KEY and MINIO_SECRET_KEY environment variables must be set."
  echo "Tip: Run 'source .env' before executing this script."
  exit 1
fi

echo "Starting MinIO backup..."
mkdir -p "${BACKUP_DIR}"

# --- The Backup Process ---
# We override the entrypoint to run a shell. Inside the shell, we perform the backup logic.
docker run --rm -i --network app-network \
  -e MINIO_ENDPOINT=minio:9000 \
  -e MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY}" \
  -e MINIO_SECRET_KEY="${MINIO_SECRET_KEY}" \
  -v "${BACKUP_DIR}:/backup" \
  alpine:latest sh -s <<EOF
set -e

# Install required packages
apk add --no-cache curl tar

# Download the latest mc binary
echo "Downloading MinIO client..."
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

echo "Configuring mc alias..."
mc alias set ${MINIO_ALIAS} http://\${MINIO_ENDPOINT} \${MINIO_ACCESS_KEY} \${MINIO_SECRET_KEY}

# Create a temporary directory to mirror all bucket data into
MIRROR_DIR="/tmp/minio_mirror"
mkdir -p "\${MIRROR_DIR}"

echo "Fetching list of buckets..."
# Get a list of all buckets by parsing the standard text output with awk
BUCKET_LIST=\$(mc ls ${MINIO_ALIAS} | awk '{print \$NF}' | sed 's/\///')

echo "Mirroring buckets..."
for bucket in \${BUCKET_LIST}; do
  if [ -n "\$bucket" ]; then
    echo "  - Mirroring bucket: \${bucket}"
    mc mirror --quiet ${MINIO_ALIAS}/"\${bucket}" "\${MIRROR_DIR}/\${bucket}"
  fi
done

echo "Creating compressed archive..."
# The archive will contain a single directory named 'minio_mirror'
tar -czf /backup/${ARCHIVE_FILENAME} -C /tmp minio_mirror

echo "Backup process inside container finished."
EOF

# --- Cleanup Old Backups ---
echo "Cleaning up old backups (older than ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name 'minio-*.tar.gz' -mtime +${RETENTION_DAYS} -delete

echo "Cleanup complete."
echo "Backup finished successfully: ${ARCHIVE_FULL_PATH}"
