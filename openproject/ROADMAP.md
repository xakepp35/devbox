# OpenProject команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Коротко, по делу и с конкретикой: цель — поднять OpenProject (Community / Enterprise) в песочнице, обеспечить repeatable build→push→deploy workflow, ежедневные бэкапы в MinIO и быстрый restore-runbook.

---

## 1. Цель проекта

* Развернуть OpenProject в compose-стеке (dev/prod-ish).
* Обеспечить процесс сборки Enterprise-образа: `docker build ./docker/prod/Dockerfile -t nexus.dev.box/openproject:16` после замены `app/models/enterprise_token.rb`.
* Настроить ежедневные бэкапы БД и assets в MinIO, документировать restore.
* CI: автоматический build→push образа в Nexus, deploy в `openproject-dev` namespace/compose.
* Документация: `README.md`, `runbook/backup-restore.md`, `ci/pipeline.yml`.

---

## 2. Область ответственности команды

* Compose / Dockerfile usage, image build & push to Nexus.
* Database (Postgres) and assets management, backup → MinIO.
* Deploy manifests (compose + Helm/kustomize) for dev cluster.
* CI templates for automated builds and pushes.
* Runbook для восстановления (DB + assets + config).
* Owners & knowledge transfer (onboarding docs).

---

## 3. Артефакты в `openproject/`

* `docker-build/`

  * `build-enterprise.sh` — скрипт клонирования/патча/сборки/пуша.
  * `Dockerfile` — (можно ссылаться на `./docker/prod/Dockerfile`).
* `docker-compose.openproject.yml` — prod-ish compose (postgres, openproject, volumes).
* `backup/`

  * `backup-db.sh`, `backup-assets.sh`, `restore-db.sh`, `restore-assets.sh` (mc-based).
* `ci/`

  * `gitlab-ci-build.yml` — template для автоматического build & push.
* `runbook/backup-restore.md` — пошаговый restore.
* `README.md`, `OWNERS.md` (контакты).

---

## 4. Near-term (0–7 дней) — Fast (пошагово)

**Цель:** локально собрать EE-образ, залить в Nexus, поднять compose-стек и получить работающий OpenProject + бэкапы.

### Шаги

1. **Подготовка репо & credentials**

   * Создать `openproject` папку в `infra-playbooks` репо. Положить `.env.example` (DB creds, NEXUS creds, MINIO creds).
2. **Клонируем исходники и патчим**

   ```bash
   git clone https://github.com/opf/openproject.git openproject-src
   cd openproject-src
   git checkout release/16   # или нужная ветка
   # В папке проекта заменяем файл
   cp ../patches/enterprise_token.rb app/models/enterprise_token.rb
   git status
   ```

   — или использовать sed/patch по необходимости.
3. **Собираем образ локально (пример)**

   ```bash
   # переменные
   NEXUS=nexus.dev.box
   TAG=16
   cd openproject-src
   docker build ./docker/prod -f ./docker/prod/Dockerfile -t ${NEXUS}/openproject:${TAG}
   ```
4. **Login → push в Nexus**

   ```bash
   # логин (CI creds хранить в GitLab variables)
   docker login ${NEXUS} -u $NEXUS_USER -p $NEXUS_PASS
   docker push ${NEXUS}/openproject:${TAG}
   ```
5. **Поднятие compose-стека (локально/песочница)**

   ```bash
   # в папке openproject/
   docker compose -f docker-compose.openproject.yml --env-file .env up -d
   ```

   * Убедиться, что Postgres + OpenProject стартуют.
6. **Бэкап (ручной тест)**

   ```bash
   # DB dump (host)
   docker exec -t openproject-postgres pg_dump -U ${OPENPROJECT_DB_USER} ${OPENPROJECT_DB_NAME} > /tmp/openproject-db-$(date +%F).sql
   # Assets archive
   tar -C /var/lib/openproject/assets -czf /tmp/openproject-assets-$(date +%F).tar.gz .
   # Загрузка в MinIO (mc)
   mc alias set localminio http://minio:9000 $MINIO_USER $MINIO_PASS
   mc cp /tmp/openproject-db-$(date +%F).sql localminio/backups/openproject/
   mc cp /tmp/openproject-assets-$(date +%F).tar.gz localminio/backups/openproject/
   ```
7. **Документировать**: записать `runbook/backup-restore.md` с этими командами и проверкой успешности.

### DoD (Near-term)

* EE image собран и запушен в `nexus.dev.box/openproject:16`.
* Compose-стек стартует, UI доступен.
* Ручный backup DB+assets успешно загружен в MinIO.
* README и runbook — минимально заполнены.

---

## 5. Mid-term (2–6 недель) — Focused

**Цель:** автоматизация CI → build/push, scheduled backups, restore drills, deploy templates, monitoring.

### Задачи

1. **CI Pipeline** — `ci/gitlab-ci-build.yml`

   * stages: `lint`, `build-image`, `scan`, `push`, `deploy-dev`.
   * builder: Kaniko / buildkit runner (no docker socket).
   * пример snippet:

     ```yaml
     build:
       stage: build
       image: gcr.io/kaniko-project/executor:latest
       script:
         - /kaniko/executor --context $CI_PROJECT_DIR --dockerfile docker/prod/Dockerfile --destination ${NEXUS}/openproject:${CI_COMMIT_SHORT_SHA} --cache=true
     push:
       stage: push
       script:
         - echo "image pushed to ${NEXUS}/openproject:${CI_COMMIT_SHORT_SHA}"
     ```
2. **Automated replace & build**:

   * CI job that applies patch to `app/models/enterprise_token.rb` from `patches/` folder before build (for EE customization).
3. **Scheduled backups**

   * Implement `backup-runner` container or cronjob on host to:

     * pg_dump -> /tmp -> mc cp to MinIO
     * archive assets -> mc cp
   * Schedules: daily DB dump, daily assets archive (or weekly for assets). Retention in MinIO lifecycle.
4. **Restore drills**

   * Periodic test: restore DB + assets into a fresh test namespace/VM. Document time and failures.
5. **Deployment templates**

   * `docker-compose.openproject.yml` → Helm chart or k8s manifests for `openproject-dev` (values: image from Nexus).
   * One-click deploy job in GitLab: commit change to `apps/openproject/values.yaml` → pipeline triggers deploy in cluster.
6. **Monitoring**

   * Health probes (liveness/readiness), Prometheus exporter for app metrics, Grafana dashboard.
7. **Security**

   * Do not store Nexus creds in repo; use GitLab CI variables (masked/protected).
   * Access via VPN and HTTPS (ingress/cert-manager) in dev.

### Deliverables

* `ci/gitlab-ci-build.yml` — automated build→push→deploy.
* `backup/` scripts + schedule (cron or k8s CronJob).
* `runbook/backup-restore.md` — tested and time-measured.
* `manifests/` for k8s deploy (Helm values).
* Monitoring config and readiness/liveness probes in manifests.

**DoD (Mid-term)**

* Automated CI builds EE image on merge to `release/16` (or tag) and pushes to Nexus.
* Scheduled backups run and archives present in MinIO.
* Test restore executed successfully in isolated environment.
* App deployed via template to dev cluster.

---

## 6. Backup & Restore — практические runbook-секции

### A. Backup OpenProject (daily)

* DB dump:

  ```bash
  PGPASSWORD=${OPENPROJECT_DB_PASS} pg_dump -Fc -h openproject-postgres -U ${OPENPROJECT_DB_USER} ${OPENPROJECT_DB_NAME} -f /tmp/openproject-$(date +%F).dump
  ```
* Assets:

  ```bash
  tar -C /var/openproject/assets -czf /tmp/openproject-assets-$(date +%F).tar.gz .
  ```
* Upload to MinIO:

  ```bash
  mc cp /tmp/openproject-$(date +%F).dump localminio/backups/openproject/
  mc cp /tmp/openproject-assets-$(date +%F).tar.gz localminio/backups/openproject/
  ```
* Verify:

  ```bash
  mc ls localminio/backups/openproject/
  mc stat localminio/backups/openproject/<file>
  ```

### B. Restore OpenProject (short)

1. Stop OpenProject app:

   ```bash
   docker compose -f docker-compose.openproject.yml stop openproject
   ```
2. Restore DB:

   ```bash
   mc cp localminio/backups/openproject/<dump>.dump /tmp/
   PGPASSWORD=${OPENPROJECT_DB_PASS} pg_restore -h openproject-postgres -U ${OPENPROJECT_DB_USER} -d ${OPENPROJECT_DB_NAME} /tmp/<dump>.dump
   ```
3. Restore assets:

   ```bash
   mc cp localminio/backups/openproject/<assets>.tar.gz /tmp/
   tar -C /var/openproject/assets -xzf /tmp/<assets>.tar.gz
   chown -R 1000:1000 /var/openproject/assets
   ```
4. Start app and run migrations if needed:

   ```bash
   docker compose -f docker-compose.openproject.yml up -d
   docker exec -it openproject bash -lc "bundle exec rake db:migrate"
   ```
5. Smoke test UI, check logs.

> Полный restore с edge-cases и чек-листом — в `runbook/backup-restore.md`.

---

## 7. Building Enterprise image — подробная инструкция (repeatable script)

Поместите скрипт `docker-build/build-enterprise.sh` в папку проекта и используйте в CI или локально.

```bash
#!/usr/bin/env bash
set -euo pipefail
# variables: adjust or export before run
SRC_REPO=${SRC_REPO:-"https://github.com/opf/openproject.git"}
SRC_DIR=${SRC_DIR:-"./openproject-src"}
BRANCH=${BRANCH:-"release/16"}
PATCH_FILE=${PATCH_FILE:-"patches/enterprise_token.rb"}
NEXUS=${NEXUS:-"nexus.dev.box"}
TAG=${TAG:-"16"}
DOCKERFILE_PATH=${DOCKERFILE_PATH:-"./docker/prod/Dockerfile"}

# 1. clone or update
if [ -d "$SRC_DIR" ]; then
  cd "$SRC_DIR"
  git fetch --all
  git checkout "$BRANCH"
  git pull --ff-only
else
  git clone --branch "$BRANCH" "$SRC_REPO" "$SRC_DIR"
  cd "$SRC_DIR"
fi

# 2. replace file
if [ -f "../$PATCH_FILE" ]; then
  cp "../$PATCH_FILE" "app/models/enterprise_token.rb"
else
  echo "ERROR: patch file not found ../$PATCH_FILE"
  exit 2
fi

# 3. build image
docker build -f "$DOCKERFILE_PATH" -t ${NEXUS}/openproject:${TAG} .

# 4. login & push
docker login ${NEXUS} -u "${NEXUS_USER}" -p "${NEXUS_PASS}"
docker push ${NEXUS}/openproject:${TAG}

echo "Built and pushed ${NEXUS}/openproject:${TAG}"
```

**Notes & best practices**

* **Do not** store `NEXUS_PASS` in plaintext; use CI variables or read from environment.
* Use Kaniko in CI (no docker socket) or GitLab runner with docker-in-docker if permitted.
* Tag images by commit SHA for traceability: `${TAG}-${CI_COMMIT_SHORT_SHA}`.

---

## 8. CI snippet (GitLab) — example

Place in `ci/gitlab-ci-build.yml` and `include` from project pipeline.

```yaml
stages:
  - build
  - push
  - deploy

variables:
  NEXUS: "nexus.dev.box"
  IMAGE: "${NEXUS}/openproject:${CI_COMMIT_SHORT_SHA}"

build-image:
  stage: build
  image: gcr.io/kaniko-project/executor:latest
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"${NEXUS}\":{\"username\":\"${NEXUS_USER}\",\"password\":\"${NEXUS_PASS}\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor --context $CI_PROJECT_DIR --dockerfile docker/prod/Dockerfile --destination $IMAGE --cache=true

push:
  stage: push
  script:
    - echo "image pushed: $IMAGE"

deploy-dev:
  stage: deploy
  when: manual
  script:
    - export KUBECONFIG=$KUBECONFIG_DEV
    - kubectl set image deployment/openproject openproject=$IMAGE -n openproject-dev
```

---

## 9. Monitoring / Healthchecks

* Add readiness/liveness endpoints in k8s manifests or use container healthcheck in compose:

  ```yaml
  healthcheck:
    test: ["CMD-SHELL","curl -f http://localhost/ || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 3
  ```
* Monitor Postgres availability, disk space on assets volume, and response times. Alert on failures.

---

## 10. Security & secrets

* Store DB passwords, Nexus creds, MinIO creds in GitLab CI variables (masked) or in ExternalSecrets (k8s).
* Limit access to image push: create Nexus user `ci-openproject` with scoped rights.
* Use HTTPS endpoints and restrict access by VPN / firewall.

---

## 11. Acceptance criteria

* EE image built locally and pushed to `nexus.dev.box/openproject:16`.
* OpenProject service starts with compose and responds to UI.
* Daily automated backup (DB + assets) appears in MinIO.
* Restore procedure restores service in test env.
* CI pipeline exists to build & push image on demand/merge.

---

## 12. Owners & communication

* **Team Owner:** (имя) — финальный ответственный за OpenProject stack.
* **Build Owner:** (имя) — отвечает за scripts и CI.
* **Backup Owner:** (имя) — отвечает за backup-runner & restore drills.
* Add contacts to `OWNERS.md`.

---

## 13. Quick checklist (copy-paste)

* [ ] Создать `openproject/` папку в репо с описанными артефактами.
* [ ] Добавить `build-enterprise.sh` и `Dockerfile` путь.
* [ ] Протестировать локальную сборку и push в Nexus.
* [ ] Поднять compose-стек и пройти smoke-test (UI up, create project).
* [ ] Настроить backup-runner и разместить первые бэкапы в MinIO.
* [ ] Написать runbook восстановления и пройти тест restore.

---

Если хочешь — могу прямо сейчас сгенерировать:

1. `docker-build/build-enterprise.sh` файл готовый к копированию;
2. `ci/gitlab-ci-build.yml` полный пример с Kaniko;
3. `runbook/backup-restore.md` подробный пошаговый сценарий с проверками и проверками ошибок.

Что делаем первым?
