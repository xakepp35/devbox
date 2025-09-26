#!/bin/sh
set -e

# Define all buckets to be created
BUCKETS="
logs
backups
"

echo "Starting MinIO bucket initialization..."

echo "Waiting for MinIO to be available..."
until /usr/bin/mc alias set myminio http://${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}; do
  echo "MinIO is not ready yet. Retrying in 2 seconds..."
  sleep 2
done

echo "MinIO is ready. Starting bucket creation..."

create_bucket_if_not_exists() {
  local bucket_name=$1
  echo "Checking bucket: ${bucket_name}..."
  
  if /usr/bin/mc ls myminio/${bucket_name} >/dev/null 2>&1; then
    echo "Bucket ${bucket_name} already exists."
  else
    echo "Creating bucket ${bucket_name}..."
    /usr/bin/mc mb myminio/${bucket_name}
    echo "Bucket ${bucket_name} created successfully."
  fi
}

# Create all buckets
for bucket in ${BUCKETS}; do
  if [ -n "${bucket}" ]; then
    create_bucket_if_not_exists "${bucket}"
  fi
done

echo "Bucket initialization completed successfully!"
echo "Total buckets processed: $(echo ${BUCKETS} | wc -w)"
