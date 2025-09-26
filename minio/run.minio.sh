docker network ls | grep -q '\bapp-network\b' || docker network create app-network
docker compose -f docker-compose.minio.yml --env-file .env up -d
