# GitLab команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Кратко и по делу: цель — рабочий, простой, повторяемый и восстанавливаемый GitLab для дев-песочницы с CI-раннерами, ежедневными бэкапами в MinIO и понятными runbook’ами.

---

## 1. Цель проекта

* Поднять **GitLab (omnibus)** в compose-стеке с отдельными DB (Postgres) и Redis.
* Настроить **ежедневные бэкапы** в `backup.dev.box` (MinIO) и протестировать восстановление.
* Обеспечить **CI runners** (group-level) и готовые **CI-шаблоны** для команд.
* Документировать всё: `README.md`, `runbook/restore.md`, `ci-templates/`.

---

## 2. Область ответственности GitLab-команды

* Docker-compose deployment (production-ish) и `.env`-файл.
* Backup/restore механика и retention policy.
* Регистрация runners + интеграция с Nexus и k8s-раннерами.
* CI-шаблоны/README/Onboarding для разработчиков.
* Мини-мониторинг и alert на состояние GitLab и бэкапов.

---

## 3. Артефакты в папке `gitlab/`

(положить файлы сюда)

* `docker-compose.gitlab.yml` — основной compose.
* `.env.example` — пример переменных.
* `backup/`

  * `backup-runner-compose.yml` / `backup-scripts/` (mc + upload).
* `ci-templates/` — `gitlab-ci-template.yml` (include).
* `README.md` — краткая инструкция.
* `runbook/restore.md` — подробный recover сценарий.
* `OWNERS.md` — текущие ответственные.

---

## 4. Near-term (ближайшая неделя) — **цели и шаги (Fast)**

### День 0 (подготовка)

* [ ] Заполнить `OWNERS.md` (имена, контакты).
* [ ] Настроить репо `infra-playbooks/gitlab` и разместить `docker-compose.gitlab.yml`, `.env.example`.

### День 1–2 (развёртывание)

* [ ] Поднять MinIO (backup.dev.box) — координация с MinIO-командой.
* [ ] На VM1 запустить:

  ```bash
  docker compose -f docker-compose.gitlab.yml --env-file .env up -d
  ```
* [ ] Проверить UI: `https://git.dev.box`, установить начальный пароль root.

### День 3 (бэкапы)

* [ ] Настроить `gitlab-backup` (backup-runner) с `mc` upload в MinIO.
* Проверка вручную:

  ```bash
  docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:create STRATEGY=copy"
  # копируем в MinIO (локально или через backup-runner)
  ```
* [ ] Убедиться, что архивы появляются в MinIO: `mc ls localminio/backups/gitlab/`

### День 4 (runners)

* [ ] Сгенерировать registration token (group runners) и передать Kubernetes-команде.
* [ ] Зарегистрировать 1 shared runner для теста (локально или в k8s).

### День 5–7 (стабилизация и документация)

* [ ] Написать `README.md` (как поднять/обновить/бэкап/восстановить).
* [ ] Сформировать `gitlab-ci-template.yml` и положить в `ci-templates/`.
* [ ] Запустить тестовый pipeline: build→push→deploy (интеграция с Nexus опционально).

**Критерии успеха (DoD) для Near-term**

* GitLab отвечает по HTTPS; root доступ работает.
* Daily backup workflow в MinIO работает и видит файлы.
* Один работающий runner, тестовый pipeline проходит.
* Runbook восстановления (короткий сценарий) — написан и проверен вручную.

---

## 5. Mid-term (2–6 недель) — **стандартизация и hardening (Focused)**

### Основные задачи

* [ ] **Автоматизация**: Ansible playbook для запуска compose стека (idempotent).
* [ ] **Перевод бэкапов на cron/cron-контейнер** с retention и lifecycle на MinIO.
* [ ] **Мониторинг**: простые метрики (disk, cpu, readiness). Alert в Slack/Telegram при падении GitLab или failed backup.
* [ ] **Security**:

  * RBAC политики: минимизировать доступы к GitLab host.
  * Rotate root/passwords и CI tokens; хранить секреты в Vault.
  * HTTPS + HSTS, настройка CSP для UI (по необходимости).
* [ ] **CI templates**: вынести `include`-файлы, examples для Node/Go/Java, security scan jobs (Trivy).
* [ ] **Recovery drills**: сценарий восстановления полностью проверен в тестовой VM (time target ≤ 15 min).

### Deliverables

* `ansible/playbooks/gitlab.yml` — idempotent installer.
* `monitoring/` — Prometheus exporter + Grafana dash (basic).
* `runbook/restore.md` — полная пошаговая инструкция (проверенная).
* `ci-templates/` — production-ready templates + docs.

**Критерии успеха (DoD) для Mid-term**

* Полностью автоматизированное поднятие GitLab на чистой VM по Ansible.
* Ежедневный backup автоматически загружается в MinIO; retention работает.
* Прошел DR тест — восстановление GitLab с нуля ≤ 15 минут (в тестовой среде).
* Раннеры надежно легендируются и имеют least-privileged доступ.

---

## 6. Инфраструктурные требования (минимально)

* VM для GitLab: **8-16 GB RAM**, 4+ vCPU, диск **>= 100 GB** (growth plan).
* Отдельный VM/кластер для MinIO (storage).
* Сеть: DNS `git.dev.box`, firewall rules разрешают 80/443/22 между dev-сетью.
* Volumes: `gitlab_config`, `gitlab_logs`, `gitlab_data`, `gitlab_pgdata`.

---

## 7. Backup & Restore — краткая инструкция (Frictionless summary)

**Backup (ручной):**

```bash
docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:create STRATEGY=copy"
# скопировать в MinIO через mc или backup-runner
```

**Restore (коротко):**

1. `docker compose -f docker-compose.gitlab.yml stop gitlab`
2. `mc cp localminio/backups/gitlab/<file>.tar /tmp/`
3. `docker cp /tmp/<file>.tar gitlab:/var/opt/gitlab/backups/`
4. `docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:restore BACKUP=<timestamp>"`
5. `docker compose up -d gitlab`

> Полный сценарий с предпроверками и order of ops — в `runbook/restore.md`.

---

## 8. Runners & CI templates — quick plan

* Создать `ci-templates/gitlab-ci-template.yml` с include:

  * stages: build, test, scan, push, deploy.
  * use Kaniko/BuildKit for builds (no docker socket).
* Регистрация runners:

  * Создать group runner (shared) token в UI → передать k8s команде.
  * Ограничить runner permissions (namespace scope for deploy jobs).
* Test jobs:

  * `ci-templates/test-pipeline.yaml` — пример pipeline, интеграция Nexus: `docker login nexus.dev.box ...`.

---

## 9. Security / Ops policies (минимум)

* Нет SSH-доступа для инженеров на GitLab host без ACC approval.
* CI variables protected/masked.
* Tokens: rotate каждые 90 дней.
* Backup keys — хранить в Vault; backup-runner имеет отдельный MinIO user/key.

---

## 10. Документация & Onboarding (Frictionless)

* В корне `gitlab/README.md`: быстрый старт (3 команды для поднятия).
* `runbook/restore.md`: подробный сценарий.
* `ci-templates/README.md`: как включать шаблон в проект.
* Onboarding-checklist: подключение к VPN, создать ключ SSH, создать project.

---

## 11. Meetings / Communication

* Daily standup 15 min (волонтёрская команда) — прогресс/блокеры.
* Демонстрация прогресса в конце недели.
* Канал: Mattermost/Slack/Telegram (указать ссылку).
* Lead: **(имя из OWNERS.md)** — ответственен за выпуск и final sign-off.

---

## 12. Риски & mitigations

* **Single host failure** → mitigation: бэкап в MinIO + playbook для быстрого восстановления.
* **OOM/CPU spike** → mitigation: monitoring + alert; прайоритизировать resize VM.
* **Утечка секретов** → mitigation: Vault, rotate keys, restricted access.

---

## 13. Опорный cheat-sheet (команды)

```bash
# поднять стек
docker compose -f docker-compose.gitlab.yml --env-file .env up -d

# ручной backup
docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:create STRATEGY=copy"

# посмотреть последние backup файлы
ls -1 /var/opt/gitlab/backups | head -n 5

# restore (в 5 шагах)
docker compose -f docker-compose.gitlab.yml stop gitlab
mc cp localminio/backups/gitlab/<file>.tar /tmp/
docker cp /tmp/<file>.tar gitlab:/var/opt/gitlab/backups/
docker exec -it gitlab sh -lc "gitlab-rake gitlab:backup:restore BACKUP=<timestamp>"
docker compose -f docker-compose.gitlab.yml up -d gitlab
```

---

## 14. Acceptance criteria (коротко)

* GitLab live по `git.dev.box` + UI доступен.
* Ежедневный автоматический backup в MinIO.
* Один зарегистрированный runner, тестовый pipeline проходит.
* Runbook restore проверен (в тестовой VM).
* Документация в `gitlab/` репо — полная и читаемая.
