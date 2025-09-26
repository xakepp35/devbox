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
