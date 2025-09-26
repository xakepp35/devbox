# внутри хоста, где запущен compose
docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:create STRATEGY=copy"
# затем скопировать файл из контейнера
docker cp gitlab:/var/opt/gitlab/backups/$(ls -1t /var/opt/gitlab/backups | head -n1) ./gitlab-backup.tar
# загрузить в minio (локально):
docker run --rm --entrypoint aws --network host -e AWS_ACCESS_KEY_ID=${MINIO_ROOT_USER} -e AWS_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD} amazon/aws-cli:latest s3 cp ./gitlab-backup.tar s3://$MINIO_BUCKET/
