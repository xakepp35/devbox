# MinIO команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Коротко, ясно и с конкретикой: цель — сделать надёжный S3-совместимый бэкап-хаус `backup.dev.box` на MinIO, обеспечить безопасный приём бэкапов от всех сервисов (GitLab, Nexus, OpenProject и т.д.), организовать политики retention, репликации и простые сценарии восстановления — и иметь возможность восстанавливать сам MinIO (данные сервера) на локальный диск или в другой хост.

---

## 1. Цель проекта

* Развернуть MinIO как централизованный S3-совместимый стор для всех бэкапов песочницы (`backup.dev.box`).
* Обеспечить простые, автоматические и проверяемые схемы: приложения → MinIO (приём), MinIO → offsite/local (реплика/архив).
* Документировать и отладить восстановление всех типов: отдельных бэкапов (GitLab .tar), целого MinIO (data dir) и «горячую» репликацию.
* Сделать всё таким, чтобы любой участник команды мог: загрузить бэкап, скачать его на локальную машину и восстановить сервис.

---

## 2. Область ответственности MinIO-команды

* Compose/daemon: `docker-compose.minio.yml` / systemd unit для MinIO.
* Пользователи/политики доступа: создание отдельных user/key для CI/backup-runner/ops.
* Buckets: организовать `gitlab/`, `nexus/`, `openproject/`, `k8s/`, `minio-backups/` и т.д.
* Lifecycle/retention: настроить автоматическое удаление старых объектов.
* Репликация/архивация MinIO → локальный диск или другая MinIO (offsite).
* Мониторинг состояния, health, и процедуру восстановления MinIO.
* Скрипты и runbooks: `backup-scripts/`, `restore/`, `runbook/minio-restore.md`.

---

## 3. Артефакты, которые должны быть в `minio/` в репо

* `docker-compose.minio.yml` — prod-ish compose (console enabled).
* `mc-config/` — примеры `mc alias`/policy scripts.
* `backup-runner/` — docker-compose + `backup-scripts/` (mc based).
* `lifecycle.json` — пример политики retention.
* `policies/` — JSON-шаблоны IAM-политик для пользователей.
* `runbook/minio-restore.md` — пошаговый процесс восстановления сервера.
* `OWNERS.md`, `README.md` — quick start.

---

## 4. Near-term (0–7 дней) — Fast actions

**Цель:** поднять MinIO, сделать базовые бакеты, выдать ключи и настроить прием бэкапов от GitLab/Nexus/OpenProject.

### Шаги

1. Поднять MinIO (на отдельной VM или в compose):

   ```bash
   docker compose -f docker-compose.minio.yml --env-file .env up -d
   ```
2. Настроить `mc` у себя и у backup-runner:

   ```bash
   mc alias set localminio http://minio:9000 MINIO_ROOT_USER MINIO_ROOT_PASSWORD
   ```
3. Создать базовые бакеты:

   ```bash
   mc mb localminio/backups/gitlab
   mc mb localminio/backups/nexus
   mc mb localminio/backups/openproject
   mc mb localminio/minio-backups     # для бекапов самого MinIO
   ```
4. Создать отдельных пользователей/ключи (не использовать root в CI):

   ```bash
   mc admin user add localminio ci-gitlab someStrongPass1
   mc admin user add localminio ci-nexus  someStrongPass2
   ```

   Назначить минимальные политики (см. ниже).
5. Настроить upload flow для приложений (пример для GitLab: `gitlab-rake` настроен на S3 → MinIO). Для остальных — backup-runner `mc cp` или `mc mirror` (см. scripts).
6. Проверить: загрузить тестовый файл → скачать на локальную машину (`mc cp localminio/backups/gitlab/test.tar ./`).

**DoD (Near-term)**

* MinIO поднят, UI доступен (`:9001`), обязательные бакеты есть.
* CI users созданы с минимальными правами.
* Тестовый бэкап загружен и скачан локально.

---

## 5. Mid-term (2–6 недель) — Focused hardening & automation

**Цель:** автоматизация, lifecycle, offsite/replication и DR-скрипты.

### Шаги

1. **Lifecycle и retention**

   * Подготовить `lifecycle.json` и импортировать:

     ```bash
     mc ilm import localminio/backups /path/to/lifecycle.json
     ```
   * Рекомендация: `RETENTION_DAYS=30` (dev) — менять по политике.
2. **Политики доступа**

   * Сделать JSON-политики для read-only / write-only / read-write и применить их к users.
   * Пример: `ci-gitlab` — `write` только в `backups/gitlab/*`.
3. **Репликация / offsite**

   * Для горячего offsite: настроить вторую MinIO (например на dev laptop или remote) и делать `mc mirror`:

     ```bash
     mc alias set remote http://remote-minio:9000 USER PASS
     mc mirror --overwrite --remove localminio/backups remote/backups
     ```
   * Для локальных архивов: `mc mirror localminio/backups /home/dev/minio-backups` или `mc cp --recursive`.
   * Для непрерывной синхронизации можно запускать `mc mirror --watch` в контейнере backup-runner (с осторожностью).
4. **Автоматизация бэкапов приложений**

   * Centralize scripts in `backup-runner/` (we did earlier). Each app should produce consistent backups into its mounted folder; runner archives and uploads to MinIO.
5. **Snapshot / server-level backup**

   * Для полного бэкапа самого MinIO (data dir): use file-system snapshot or `tar` of `/data` when MinIO is stopped (clean restore):

     ```bash
     docker compose -f docker-compose.minio.yml stop minio
     tar -C /path/to/minio/data -czf /tmp/minio-data-$(date +%FT%H%M).tar.gz .
     mc cp /tmp/minio-data-$(date...).tar.gz localminio/minio-backups/
     docker compose -f docker-compose.minio.yml up -d
     ```
   * Prefer snapshots (LVM/ZFS) on storage host for consistency in production.
6. **Monitoring & Alerts**

   * Collect health with `mc admin info` and metrics endpoint; alert on disk usage, unhealthy drives, auth failures.
7. **DR drills**

   * Monthly: restore one GitLab / Nexus / OpenProject backup from MinIO into test environment.
   * Quarterly: full MinIO server restore onto spare VM.

**DoD (Mid-term)**

* Lifecycle работает, старые объекты удаляются по плану.
* Минимум два offsite-реплики (или локальный архив) регулярно обновляются.
* Runbook restore MinIO проверен и время восстановления документировано.

---

## 6. Как бекапить *всё* в MinIO — практический гайд

1. Принцип: каждый сервис делает *локальную* бэкап-операцию (dump / tar / export), а затем либо:

   * сам **выкладывает** файл в MinIO (если умеет S3), или
   * кладёт файл в общую папку на хосте, где `backup-runner` собирает и загружает в MinIO с правильной структурой (recommended).
2. **Примеры:**

   * **GitLab (omnibus)** — в `gitlab.rb` задать `backup_upload_connection` на MinIO (S3) — GitLab сам выгрузит backup-архив туда. Также можно вручную `gitlab-rake gitlab:backup:create` и потом `mc cp`.
   * **Nexus** — ставим `nexus-backup.sh` который тарит `/nexus-data` и `mc cp` в `backups/nexus/`.
   * **OpenProject** — `pg_dump` + архив assets → `mc cp` в `backups/openproject/`.
3. **Naming convention** (важно):

   ```
   backups/<service>/<YYYYMMDDTHHMMSS>-<host>.tar.gz
   ```

   — так проще искать и чистить.
4. **Upload example (backup-runner):**

   ```bash
   mc alias set localminio http://minio:9000 $MINIO_USER $MINIO_PASS
   mc cp /tmp/gitlab-backup-20250925.tar.gz localminio/backups/gitlab/
   ```
5. **Verify after upload:**

   ```bash
   mc ls localminio/backups/gitlab/
   mc stat localminio/backups/gitlab/<file>
   ```

---

## 7. Как бекапить сам MinIO (data dir) — варианты

### A. **Cold backup (recommended for consistent restore)**

* Stop MinIO, archive data directory, copy archive to MinIO:

  ```bash
  docker compose -f docker-compose.minio.yml stop minio
  tar -C /var/lib/minio -czf /tmp/minio-data-$TS.tar.gz .
  mc cp /tmp/minio-data-$TS.tar.gz localminio/minio-backups/
  docker compose -f docker-compose.minio.yml up -d
  ```
* Плюсы: консистентный снимок; Минусы: downtime.

### B. **Hot backup (no downtime) — mirror approach**

* Mirror entire buckets to another MinIO or to local FS:

  ```bash
  # copy MinIO -> local disk
  mc mirror localminio/backups /home/dev/minio-backups
  # or MinIO -> remote MinIO
  mc alias set remote http://remote:9000 user pass
  mc mirror --overwrite --remove localminio/backups remote/backups
  ```
* Плюсы: нет простоев; Минусы: может быть не-атомарно — часть изменений может попасть позднее.

### C. **Storage snapshot**

* If storage is on LVM/ZFS, use snapshot mechanism — best for speed and consistency. Then archive snapshot and offload to MinIO.

### D. **Versioning & Object Lock**

* Optionally enable object versioning (if compliance required) or object-lock for WORM. (Настраивается на bucket level; учтите влияние на storage growth.)

---

## 8. Политики доступа и безопасность (конкретно)

1. **Не использовать root creds в CI.** Создать per-service users:

   * `ci-gitlab` — write to `backups/gitlab/` only
   * `ci-nexus` — write to `backups/nexus/` only
   * `ops` — read/write to all backups
2. **Пример команд:**

   ```bash
   mc admin user add localminio ci-gitlab strongpass123
   mc policy set download localminio/backups/gitlab   # read
   mc policy set upload localminio/backups/gitlab     # (if exist) or use admin policy binding
   ```

   (Если нужно — применить JSON-политику через `mc admin policy add` и привязать к user: `mc admin policy set localminio <policy-name> user=<username>`.)
3. **TLS:** ставьте TLS на MinIO (nginx reverse proxy или включить TLS в MinIO) — обязательно для публичного доступа.
4. **Rotate keys:** ротация ключей каждые N дней; держать root key offline, выдавать per-service keys.
5. **Firewall / VPN:** открывать MinIO API только внутри VPN / доверенной сети.

---

## 9. Lifecycle и retention — пример

`lifecycle.json` (удалять объекты старше 30 дней):

```json
{
  "Rules": [
    {
      "ID": "retention",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": 30 }
    }
  ]
}
```

Импорт:

```bash
mc ilm import localminio/backups /path/to/lifecycle.json
```

(Настройте разные правила для `minio-backups` — возможно хранить дольше).

---

## 10. Monitoring, health и ops команды

* Проверка статуса:

  ```bash
  mc admin info localminio
  mc admin service status localminio
  ```
* Логи: `docker logs -f minio` или systemd journal.
* Метрики: включить Prometheus endpoint MinIO (обычно `/minio/prometheus/metrics`), подключить Prometheus & Grafana.
* Alerts: диск > 80%, failed upload, authentication failures.

---

## 11. Restore — пошаговые сценарии (коротко)

### A. Восстановить отдельный бэкап (например GitLab)

1. Скачиваем файл:

   ```bash
   mc cp localminio/backups/gitlab/<file>.tar.gz /tmp/
   ```
2. Передаём в сервис или распаковываем по инструкции сервиса (например GitLab restore process).
3. Тестируем.

### B. Восстановить весь MinIO на новом хосте (cold restore)

1. Поднять чистый MinIO экземпляр (container).
2. Скопировать архив данных:

   ```bash
   mc cp localminio/minio-backups/minio-data-<TS>.tar.gz /tmp/
   ```
3. Остановить minio, распаковать в data dir и запустить:

   ```bash
   docker compose -f docker-compose.minio.yml stop minio
   tar -C /var/lib/minio -xzf /tmp/minio-data-<TS>.tar.gz
   chown -R 1000:1000 /var/lib/minio   # user id MinIO
   docker compose -f docker-compose.minio.yml up -d
   ```
4. Проверить список бакетов и объекты: `mc ls localminio/`.

---

## 12. DR drills & тесты (регламент)

* **Daily:** мониторинг, проверка успешности последних загрузок.
* **Weekly:** тест загрузки/скачивания случайного бэкапа (smoke test).
* **Monthly:** restore одного сервиса из MinIO в тестовой среде.
* **Quarterly:** полный restore MinIO на spare VM (time target — документировать).

---

## 13. Риски & mitigations

* **Рост расходов диска** — mitigation: lifecycle + alerts + offsite archive.
* **Утечка credentials** — mitigation: Vault + key rotation.
* **Corruption of data directory** — mitigation: use erasure-code/distributed MinIO or regular server backups + offsite mirror.
* **Single-node MinIO fails** — mitigation: mirror to remote MinIO or use distributed MinIO cluster.

---

## 14. Quick commands cheat-sheet (reference)

```bash
# настроить alias
mc alias set localminio http://minio:9000 MINIO_ROOT_USER MINIO_ROOT_PASSWORD

# создать bucket
mc mb localminio/backups/gitlab

# загрузить файл
mc cp ./file.tar.gz localminio/backups/gitlab/

# посмотреть список
mc ls localminio/backups/gitlab/

# зеркалирование MinIO -> локальная папка
mc mirror localminio/backups /home/dev/minio-backups

# зеркалирование MinIO -> удалённая MinIO
mc alias set remote http://remote:9000 USER PASS
mc mirror --overwrite --remove localminio/backups remote/backups

# lifecycle import
mc ilm import localminio/backups ./lifecycle.json

# создать user
mc admin user add localminio ci-gitlab strongPass

# проверить сервис
mc admin info localminio
mc admin service status localminio
```

---

## 15. Owners & communication

* **Team Owner:** (вставьте имя) — ответственный за delivery и DR sign-off.
* **On-call:** (имя/телеграм) — 1st responder.
* Канал связи: общий канал infra / telegram / mattermost.

---

## 16. Checklist (кратко — что сделать сейчас)

* [ ] `docker-compose.minio.yml` в `minio/` + `.env` настроен
* [ ] Buckets созданы (`gitlab`, `nexus`, `openproject`, `minio-backups`)
* [ ] Per-service users созданы и credentials переданы в GitLab CI (masked)
* [ ] `backup-runner` развернут и умеет загружать файлы в MinIO
* [ ] Lifecycle установлен и протестирован
* [ ] Mirror/Archive скрипт на место (локальный диск/offsite) + тестовая реплика
* [ ] Runbook `minio-restore.md` написан и прогнан в тестовом restore

---

Если хочешь, могу прямо сейчас:

1. сгенерировать `docker-compose.minio.yml` production-ish (с TLS hints и volumes),
2. написать `runbook/minio-restore.md` подробно с командами и проверками,
3. подготовить `policies/` — JSON-шаблоны политик для `ci-gitlab`, `ci-nexus`, `ops` и пример команд `mc admin policy add` / `mc admin policy set`.

Какой из трёх пунктов делаем в первую очередь?
