docker compose -f docker-compose.gitlab.yml stop gitlab
docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:restore BACKUP=<timestamped-filename-without-.tar>"
