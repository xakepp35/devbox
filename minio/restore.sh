#!/usr/bin/env bash
set -euo pipefail

# This script restores a MinIO backup created by the backup script.
# Usage: ./restore.sh <backup-file>
# Example: ./restore.sh minio_backups/minio-2025-09-26.tar.gz

# ------------- configurable -------------
MINIO_ALIAS="minio_restore_alias"   # An internal alias for mc
# ----------------------------------------

source .env

# --- Pre-flight Checks ---
if [ -z "${MINIO_ACCESS_KEY-}" ] || [ -z "${MINIO_SECRET_KEY-}" ]; then
  echo "Error: MINIO_ACCESS_KEY and MINIO_SECRET_KEY environment variables must be set."
  echo "Tip: Run 'source .env' before executing this script."
  exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup-file>"
  echo "Example: $0 minio_backups/minio-2025-09-26.tar.gz"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file '$BACKUP_FILE' not found."
  exit 1
fi

# --- Confirmation ---
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!                    WARNING: DESTRUCTIVE ACTION                   !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "This script will restore the backup from '$(basename "$BACKUP_FILE")'."
echo "It will OVERWRITE any existing files in buckets with the same name."
echo "It will CREATE buckets if they do not exist on the target server."
echo ""
read -p "Are you sure you want to continue? (y/N): " confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
  echo "Restore cancelled."
  exit 0
fi

echo "Starting MinIO restore..."

# Create a temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract the backup
echo "Extracting archive: $(basename "$BACKUP_FILE")..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
echo "Extraction complete."

# --- The Restore Process ---
echo "Mirroring data to MinIO..."
docker run --rm -i --network app-network \
  -e MINIO_ENDPOINT=minio:9000 \
  -e MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY}" \
  -e MINIO_SECRET_KEY="${MINIO_SECRET_KEY}" \
  -v "$TEMP_DIR:/restore:ro" \
  alpine:latest /bin/sh <<'EOF'
set -e

# Install required packages
apk add --no-cache curl

# Download the latest mc binary
echo "Downloading MinIO client..."
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

echo "Configuring mc alias..."
mc alias set minio_restore_alias http://${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}

# Check if the minio_mirror directory exists
if [ ! -d "/restore/minio_mirror" ]; then
  echo "Error: Invalid backup format. Expected 'minio_mirror' directory."
  exit 1
fi

cd /restore/minio_mirror

# Restore each bucket
echo "Restoring buckets..."
for bucket_dir in */; do
  if [ -d "$bucket_dir" ]; then
    bucket_name=${bucket_dir%/}
    echo "  - Processing bucket: ${bucket_name}"
    
    # Create bucket if it doesn't exist
    mc mb minio_restore_alias/${bucket_name} --ignore-existing 2>/dev/null || true
    
    # Mirror the data back
    mc mirror --overwrite "${bucket_dir}" minio_restore_alias/${bucket_name}/
  fi
done

echo "Restore process completed successfully!"
EOF

echo "Restore finished."
