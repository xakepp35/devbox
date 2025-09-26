# Nexus команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Кратко, по делу и с конкретикой: цель — надёжный, понятный и быстро восстанавливаемый Nexus Registry (docker/maven/npm и пр.) для дев-песочницы. Каждый шаг — runnable, документируемый, тестируемый.

---

# 1. Краткая задача

Поднять Sonatype Nexus 3 как централизованный артефакт-репозиторий для CI: Docker hosted, proxy (Docker Hub/Maven Central), npm/maven репозитории, ежедневные бэкапы в `backup.dev.box` (MinIO), простые правила retention и runbook восстановления.

---

# 2. Область ответственности

* Compose-стек: `docker-compose.nexus.yml` + volumes.
* Настройка репозиториев (Docker hosted/proxy, Maven proxy, npm).
* Бэкап/restore: tar/rsync snapshot → MinIO (mc).
* Создание CI service account (ci-user) и secrets для GitLab.
* Мониторинг здоровья, базовые alert’ы и cleanup policies.
* Документация: `README.md`, `runbook/restore.md`, `OWNERS.md`.

---

# 3. Артефакты в папке `nexus/`

* `docker-compose.nexus.yml` (production-ish)
* `.env.example`
* `backup/`

  * `nexus-backup.sh` (archiving → mc upload)
  * `restore.sh` (tar → restore)
* `repos/`

  * `create-docker-hosted.json` (пример REST payload)
  * `create-maven-proxy.json`
* `README.md` (быстрый старт)
* `runbook/restore.md` (пошаговый rebuild)

---

# 4. Near-term (0–7 дней) — быстрые результаты (Fast)

**Цель:** увидеть работающий Nexus, настроить 1 docker hosted repo, настроить бэкап → MinIO, протестировать push/pull.

### Задачи (пошагово)

1. ✅ Поднять MinIO (координация с MinIO-командой).
2. ✅ Развернуть Nexus (compose):

   ```bash
   docker compose -f docker-compose.nexus.yml --env-file .env up -d
   ```
3. ✅ Получить initial admin password:

   ```bash
   docker exec nexus cat /nexus-data/admin.password
   ```
4. ✅ Войти в UI `http://nexus.dev.box:8081`, сменить пароль admin, создать `ci-user` (role: nx-admin или более скромный — nx-deployer для Docker hosted).
5. ✅ Создать Docker hosted repo (UI или REST). Пример REST (пример payload в `repos/create-docker-hosted.json`):

   ```bash
   curl -u admin:<pass> -X POST "http://nexus.dev.box:8081/service/rest/v1/repositories/docker/hosted" \
     -H "Content-Type: application/json" -d @create-docker-hosted.json
   ```
6. ✅ Прописать credentials `NEXUS_USER` / `NEXUS_PASS` в GitLab CI variables (masked, protected).
7. ✅ Тест: из CI runner (или локально) docker login → docker push → docker pull.
8. ✅ Настроить ежедневный бэкап (скрипт `nexus-backup.sh`) и загрузку в MinIO с использованием `mc` (или `aws-cli`).

### Критерии успеха (DoD)

* Nexus UI доступен, admin пароль сменён.
* Docker hosted repo создан и принимает push/pull.
* Бэкап загружается в bucket `backups/nexus/` в MinIO.
* Runbook восстановления (короткий) создан и протестирован вручную.

---

# 5. Mid-term (2–6 недель) — стандарты и надёжность (Focused)

**Цель:** сделать Nexus устойчивым, автоматизировать управление, настроить retention и мониторинг.

### Задачи

1. **Автоматизация deploy**: Ansible/Makefile для `docker compose` deploy + initial config import (repository definitions).
2. **Blobstore & storage**:

   * Убедиться, что `nexus-data` на SSD/RAID или NFS с snapshot (в зависимости от infra).
   * Документировать место хранения blobstore, скорости IO.
3. **Backup improvements**:

   * Перенести из простого `tar` в регулярный snapshot + offload в MinIO.
   * Настроить lifecycle/retention (на MinIO) — 30 дней по умолчанию.
4. **Repository management**:

   * Создать шаблоны repo (Docker hosted, Maven proxy + group, npm proxy) в `repos/`.
   * Настроить scheduled tasks в Nexus: cleanup unused components, compaction if needed.
5. **Security & Access**:

   * Создать service accounts: `ci-docker-push`, `ci-maven-publish` с минимальными правами.
   * Ограничить UI доступ: admin users limited; audit logging на.
6. **Monitoring & Alerts**:

   * Включить healthcheck endpoint; подключить exporter (Nexus Prometheus plugin or jmx exporter).
   * Alert на: `nexus down`, `disk usage > 80%`, `backup failed`.
7. **Performance tuning**:

   * JVM params (`-Xms -Xmx -XX:MaxDirectMemorySize`), garbage collection tuning.
   * Тесты нагрузочного push/pull под expected load.
8. **DR drills**:

   * Провести тест полного восстановления на чистой VM (time target ≤ 15–30 min).
9. **Docs**:

   * `runbook/restore.md` — полный сценарий; `README.md` — quick start; `OWNERS.md` — контакты.

### Deliverables

* `ansible/playbooks/nexus.yml` (idempotent).
* `repos/*.json` — scripts to create repos via REST.
* `monitoring/` — exporter config and Grafana dashboard snippet.
* `runbook/restore.md` — проверенный.

---

# 6. Backup & Restore — Руководство (Frictionless summary)

## Backup (recommended simple approach)

1. Остановить Nexus (рекомендуется для консистентного бэкапа):

   ```bash
   docker compose -f docker-compose.nexus.yml stop nexus
   ```
2. Создать tar архивацию `nexus-data`:

   ```bash
   TS=$(date -u +%Y%m%dT%H%M%SZ)
   tar -C /path/to/nexus-data -czf /tmp/nexus-backup-$TS.tar.gz .
   ```
3. Загрузить в MinIO:

   ```bash
   mc alias set localminio http://minio:9000 $MINIO_USER $MINIO_PASS
   mc cp /tmp/nexus-backup-$TS.tar.gz localminio/backups/nexus/$TS.tar.gz
   ```
4. Запустить Nexus:

   ```bash
   docker compose -f docker-compose.nexus.yml up -d nexus
   ```

> Примечание: для нулевого даунтайма рассмотреть подход с hot backup/прогоном tasks и использованием blobstore replication (enterprise) или snapshot на storage layer.

## Restore (коротко)

1. Остановить Nexus:

   ```bash
   docker compose -f docker-compose.nexus.yml stop nexus
   ```
2. Скопировать архив из MinIO:

   ```bash
   mc cp localminio/backups/nexus/<TS>.tar.gz /tmp/
   ```
3. Распаковать в `nexus-data` (предварительно очистив папку):

   ```bash
   rm -rf /path/to/nexus-data/*
   tar -C /path/to/nexus-data -xzf /tmp/<TS>.tar.gz
   chown -R 200:200 /path/to/nexus-data   # nexus user id обычно 200
   ```
4. Запустить Nexus:

   ```bash
   docker compose -f docker-compose.nexus.yml up -d nexus
   ```
5. Проверить UI и логи (`docker logs -f nexus`).

**DR test**: выполнять раз в месяц в изолированной VM.

---

# 7. Integration with GitLab CI — quick actions

* Создать `ci-user` и токен или использовать `ci-docker-push` (user/password) и положить в GitLab CI variables:

  * `NEXUS_REGISTRY=nexus.dev.box:8082` (или mapping)
  * `NEXUS_USER=ci-docker-push`
  * `NEXUS_PASS=<secret>`
* Пример `.gitlab-ci.yml` snippet:

  ```yaml
  variables:
    REGISTRY: $NEXUS_REGISTRY
    IMAGE: $REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_SHORT_SHA

  build:
    stage: build
    script:
      - echo $NEXUS_PASS | docker login $NEXUS_REGISTRY -u $NEXUS_USER --password-stdin
      - docker build -t $IMAGE .
      - docker push $IMAGE
  ```
* Тестовый pipeline: build → push → pull from another job.

---

# 8. Security & Access control (минимум)

* Сменить admin password сразу. Не хранить root credentials в репо.
* Создать специализированные CI users с минимальными привилегиями.
* Включить HTTPS через reverse proxy (nginx/ingress) — TLS mandatory.
* Включить audit logging (System → Audit logs).
* Периодическая ротация credentials (90 дней) и хранение ключей в Vault.

---

# 9. Monitoring & Alerts (минимум)

* Health endpoint: `http://nexus:8081/service/metrics` (or JMX) — настроить exporter.
* Alerts:

  * Nexus process down → pager/Slack.
  * Disk usage > 75% → warn, > 90% → critical.
  * Backup upload failed → critical.
* Grafana: panel for repository sizes, blobstore usage, request rates.

---

# 10. Infra & sizing (рекомендации)

* Минимум для dev-pesочницы: **2 vCPU, 4–8 GB RAM**, HDD/SSD ≥ 100 GB. Для комфортной работы (при многих pushes) — **4 vCPU, 8–16 GB RAM** и fast disk.
* JVM: `-Xms1g -Xmx2g -XX:MaxDirectMemorySize=1g` — tune по нагрузке (`INSTALL4J_ADD_VM_PARAMS`).
* Volume: `nexus-data` на отдельном диске/volume; snapshot capability желательна.

---

# 11. Deliverables & Acceptance Criteria

* Запущенный Nexus, доступный по `nexus.dev.box:8081`.
* Docker hosted repo принимает push/pull.
* Ежедневный backup в MinIO и tested restore procedure (dry run).
* CI user создан, credentials положены в GitLab variables и pipeline успешно пушит image.
* Документы: `README.md`, `runbook/restore.md`, `OWNERS.md` в папке `nexus/`.
* Basic monitoring + alert на backup failures and disk usage.

---

# 12. Quick commands cheat-sheet

```bash
# поднять nexus
docker compose -f docker-compose.nexus.yml --env-file .env up -d

# admin password
docker exec nexus cat /nexus-data/admin.password

# создать tar backup (host)
TS=$(date -u +%Y%m%dT%H%M%SZ)
tar -C /path/to/nexus-data -czf /tmp/nexus-backup-$TS.tar.gz .

# загрузить в minio (mc)
mc alias set localminio http://minio:9000 $MINIO_USER $MINIO_PASS
mc cp /tmp/nexus-backup-$TS.tar.gz localminio/backups/nexus/$TS.tar.gz

# restore example (host)
docker compose -f docker-compose.nexus.yml stop nexus
rm -rf /path/to/nexus-data/*
mc cp localminio/backups/nexus/<TS>.tar.gz /tmp/
tar -C /path/to/nexus-data -xzf /tmp/<TS>.tar.gz
chown -R 200:200 /path/to/nexus-data
docker compose -f docker-compose.nexus.yml up -d nexus
```

---

# 13. Риски & mitigations

* **Disk full / IO bottleneck** — мониторинг + alert; план расширения storage.
* **Corrupted blobstore** — регулярно проверять backups, тестовые restores.
* **Exposed admin UI** — TLS + firewall + VPN; restrict admin users.

---

# 14. Owners & контакты

* **Team Owner:** (вставьте имя) — финальное sign-off.
* **On-call:** (вставьте имя/телеграм) — 1st responder по инцидентам.
* `OWNERS.md` в папке содержит актуальные контакты.

---

Если хочешь — могу прямо сейчас:

* сгенерировать `repos/create-docker-hosted.json` и `curl`-скрипт для быстрой автоматической регистрации репо;
* подготовить `nexus-backup.sh` и `restore.sh` под ваши пути и дать финальный `docker-compose.nexus.yml` с JVM params;
* написать `runbook/restore.md` пошагово (скрипты + проверки).

Что делаем первым — скрипт создания репо, бэкап-скрипт или runbook?
