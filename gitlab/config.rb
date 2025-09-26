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
