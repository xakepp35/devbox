# K8s (microk8s) команда

**Стиль:** FFF — *Fast. Focused. Frictionless.*
Коротко, по делу и с конкретикой: цель — развернуть повторяемый, понятный и восстанавливаемый dev-кластер на **microk8s** (snap), который будет основой для раннеров, песочниц, ingress, storage и бэкапов.

> ⚠️ корректная команда установки — `sudo snap install microk8s --classic`.

---

## 1. Цель / миссия

* Быстро и надёжно предоставить **dev-k8s**: ingress, LB, storage, CI-runners, мониторинг и простые шаблоны деплоя.
* Сделать кластер **повторяемым** (скрипты/Ansible/README), **восстанавливаемым** (Velero → MinIO) и **безопасным** (RBAC, network policies).
* Уменьшить порог вхождения: любой участник команды должен уметь поднять/ресторить базовый кластер по runbook за ограниченное время.

---

## 2. Область ответственности k8s-команды

* Установка microk8s на ноды и поддержка кластера.
* Настройка core-аддонов: dns, ingress, metallb, storage, registry, helm3, metrics.
* Прописать Node pools (infra vs workers), taints/labels.
* Интеграция с GitLab runners (group runners).
* Настройка backup/restore (Velero → MinIO) и тесты DR.
* Мониторинг (Prometheus/Grafana) и логирование (Loki/EFK).
* Документация: `k8s/README.md`, `runbook/restore.md`, `ansible/` или `install.sh`.

---

## 3. Артефакты, которые кладём в `k8s/`

* `install/`

  * `microk8s-install.sh` (idempotent скрипт с необходимыми проверками)
  * `join-node.sh` (шаблон для добавления нод)
* `manifests/`

  * `ingress/` (nginx ingress example)
  * `metalLB.yaml` / instructions (ip-pool placeholder)
  * `nfs-provisioner/` или `longhorn/` helm values
  * `gitlab-runner-deployment.yaml` (k8s runner template)
* `backup/`

  * `velero-install.sh` + velero schedules to MinIO
  * `etcd-snapshot-guidelines.md` (conceptual)
* `monitoring/` — prometheus/grafana helm values
* `README.md` и `runbook/restore.md` (пошаговые инструкции)
* `OWNERS.md` (контакты)

---

## 4. Требования / предпосылки (минимум)

* 3 ноды для кластера (рекомендуется) — роль control+worker на каждой (microk8s кластер объединяется через join).
* Каждая нода: Ubuntu LTS, swap off, NTP, доступ по SSH.
* Сеть: статические IP / DHCP reservation; выделенный пул IP для MetalLB (например 10.10.10.240-10.10.10.250).
* Storage: *production target uses NFS* → настроить NFS server и external-provisioner в k8s. Для dev можно пилотировать Longhorn (опционально).
* MinIO (backup.dev.box) доступен для Velero.

---

## 5. Quick-start (коротко, reproducible шаги)

1. На каждой ноде:

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s $USER && newgrp microk8s
sudo microk8s status --wait-ready
# выключить swap, проверить ntp
```

2. На первой ноде:

```bash
sudo microk8s add-node
# получите команду join вида: microk8s join <ip>:25000/<token>
```

3. На остальных нодах — выполнить возвращённую команду `microk8s join ...`.
4. На master:

```bash
sudo microk8s status --wait-ready
sudo microk8s enable dns ingress registry helm3 storage
# включаем MetalLB с вашим пулом:
sudo microk8s enable metallb:<IP_RANGE>
```

5. Проверить: `microk8s kubectl get nodes` и `microk8s kubectl get all -A`.

> В репо положить `microk8s-install.sh` с этими же командами и параметрами.

---

## 6. Near-term (0–7 дней) — Fast tasks (пошагово)

**Цель:** получить рабочий кластер с ingress, LB, storage, registry и регистрацией 1 runner.

1. Подготовка нод (Infra/ops):

   * [ ] выключить swap, настроить NTP, создать user `microk8s`/доступ SSH, прописать DNS/hosts.
2. Установка microk8s и join:

   * [ ] выполнить `snap install`, выполнить `add-node`/`join`.
3. Включение базовых аддонов:

   * [ ] `microk8s enable dns ingress registry helm3 storage`
   * [ ] `microk8s enable metallb:<POOL>` (заменить IP range)
4. Storage:

   * [ ] Подключить NFS-provisioner (helm/kustomize) → создать `StorageClass` `nfs-sc` (prod)
5. GitLab-runner:

   * [ ] Развернуть `gitlab-runner` в k8s (Helm chart) — зарегистрировать с group token.
6. Dev test:

   * [ ] Деплой простого `hello` app, выставить Ingress `my-app.dev.dev.box` и проверить доступ.
7. Backup initial:

   * [ ] Установить Velero с плагином для MinIO (backup bucket) — сделать первый ручной backup.
8. Документация:

   * [ ] `README.md` с командами установки и быстрым тестом.

**DoD (Near-term):**

* Кластер жив и ноды `Ready`.
* Ingress + MetalLB возвращают IP и служат сервисам.
* StorageClass `nfs-sc` работает, PV provisioning тестирован.
* Один работающий GitLab runner в кластере.
* Velero может сделать backup ресурсов в MinIO.

---

## 7. Mid-term (2–6 недель) — Focused improvements

**Цель:** автоматизация, observability, DR-процедуры, политика безопасности.

1. Автоматизация & IaC:

   * [ ] Ansible / bash installer (`install/microk8s-install.sh`) → idempotent.
   * [ ] Playbook для провижена нод и join.
2. HA & Node topology:

   * [ ] Описать pool’ы: `infra` (taint: infra=true:NoSchedule → для GitLab/Nexus если нужно), `worker` (для dev workloads).
   * [ ] Настроить labels: `node-role.kubernetes.io/infra=`, `node-role.kubernetes.io/worker=`.
3. Storage & PV:

   * [ ] В production использовать `nfs-subdir-external-provisioner` (dynamic PV) — values & docs.
   * [ ] Для тестирования Longhorn — deploy и оценка performance.
4. Backup / DR:

   * [ ] Velero schedules + restore playbook: `daily`, `weekly`, `monthly`.
   * [ ] Test DR: полное восстановление namespace из Velero в тестовом кластере.
   * [ ] Документировать порядок restore (etcd, PV, then apps).
5. Monitoring & Logging:

   * [ ] Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager).
   * [ ] Deploy Loki + Promtail или EFK для логов.
   * [ ] Создать набор дашбордов: nodes, pods, PVC usage, runner job durations.
6. Security & Policies:

   * [ ] OPA/Gatekeeper для базовых правил (deny privileged containers, deny hostPath).
   * [ ] NetworkPolicies для зон (infra ns vs dev ns).
   * [ ] Secrets: ExternalSecrets operator (Vault integration) or SealedSecrets.
7. CI/CD polish:

   * [ ] Helm chart / kustomize для standard app, app templates for one-click provision.
   * [ ] Auto-scale runners (if needed).
8. Observability & Alerts:

   * [ ] Alerts to Slack/Telegram for nodeNotReady, PVC fill > 80%, backup failure.

**Deliverables (Mid-term):**

* `ansible/` scripts & idempotent installer.
* Velero schedules + tested restore playbook.
* Monitoring stack with basic alerts.
* Security baseline (Gatekeeper policies + NetworkPolicies).
* README + runbook DR steps.

---

## 8. Addons / recommended components (конкретно)

* `dns` (microk8s addon)
* `ingress` (nginx)
* `metallb` (LB for bare metal) — configure IP pool
* `storage` (microk8s builtin hostpath) **+** NFS provisioner for dynamic PVs (`nfs-subdir-external-provisioner`)
* `registry` (local registry for fast caching)
* `helm3` (charts)
* `metrics-server`, `prometheus`/`grafana` (monitoring)
* `velero` (backup to MinIO) — install via helm and configure MinIO plugin
* `gitlab-runner` (helm chart) — executor=kubernetes
* `loki` + `promtail` or `efk` for logs
* `cert-manager` for TLS via ACME (if public DNS available)

---

## 9. Node topology & scheduling policy (recommended)

* **infra** nodes (1–2 nodes) — reserved for critical infra (if you choose to place GitLab/Nexus in k8s). Taints: `infra=true:NoSchedule`.
* **worker** nodes (rest) — run dev workloads and CI jobs.
* Labels examples:

  * infra: `node-role.kubernetes.io/infra=true`
  * worker: `node-role.kubernetes.io/worker=true`
* Resource quotas & LimitRanges per namespace to avoid noisy-neighbor.

---

## 10. Storage strategy (prod = NFS)

* **Prod target**: NFS server (external), use `nfs-subdir-external-provisioner` as StorageClass `nfs-sc`. Configure proper mount options and snapshot ability on NFS host.
* **Dev experiments**: Longhorn (block replication) for local tests; evaluate IO.
* **Best practice**: stateless apps on workers; stateful only with PV on `nfs-sc`.

---

## 11. Backup & restore (Velero + concept)

* Install Velero with plugin `velero-plugin-for-aws` configured for MinIO endpoint.
* Schedules: `daily` (namespaces: infra, kube-system snapshot?), `weekly` (full cluster), `monthly` (offsite).
* For PV snapshots: depends on storage provider (NFS typically needs file copy; block storage supports snapshot). Use Velero for CRDs+manifests+meta; PV handling via snapshots if supported.
* DR playbook: rebuild cluster → restore Velero full snapshot → wait for PVs → validate services.

---

## 12. GitLab Runner in cluster (quick)

* Install `gitlab-runner` via Helm chart in namespace `gitlab-runner`.
* Configure runner executor = `kubernetes`, with `rbac` and `serviceAccount` limited to namespaces where it should deploy.
* Tag runners: `k8s-build`, `k8s-deploy`.
* Provide CI examples in `k8s/ci-examples/`.

---

## 13. Monitoring & logging (minimum viable)

* Deploy `kube-prometheus-stack` (helm). Create dashboards for nodes, pods, PVC usage.
* Configure Alertmanager → Slack/Telegram.
* Deploy Loki + promtail (lightweight) for logs; or EFK if needed.

---

## 14. Security baseline

* Enforce RBAC: developers scoped to their namespaces.
* Gatekeeper/OPA policies: deny privileged, deny hostPath, require image from approved registry (Nexus).
* NetworkPolicies: default deny between namespaces, allow ingress where required.
* Secrets lifecycle: ExternalSecrets + Vault or SealedSecrets.

---

## 15. Test checklist / Acceptance criteria

* [ ] `kubectl get nodes` → все ноды `Ready`.
* [ ] Ingress exposes test app at `app.dev.dev.box` via MetalLB IP.
* [ ] `StorageClass` `nfs-sc` can dynamically provision PVC → Pod gets bound.
* [ ] One GitLab Runner registered and can run a build job (Kaniko) and push to Nexus.
* [ ] Velero does `velero backup create initial-backup` and backup files appear in MinIO.
* [ ] Prometheus collects node metrics; alert triggers on synthetic failure.
* [ ] `runbook/restore.md` проверен вручную (partial restore).

---

## 16. Quick commands (cheat-sheet)

```bash
# статус microk8s
sudo microk8s status --wait-ready
# enable addons
sudo microk8s enable dns ingress registry helm3 storage
# enable metallb with pool
sudo microk8s enable metallb:10.10.10.240-10.10.10.250
# add node (on master)
sudo microk8s add-node
# join on worker (command returned by add-node)
sudo microk8s join <MASTER_IP>:25000/<TOKEN>
# kubectl
microk8s kubectl get nodes
microk8s kubectl get all -A
# helm
microk8s helm3 repo add stable https://charts.helm.sh/stable
microk8s helm3 repo update
microk8s helm3 install gitlab-runner gitlab/gitlab-runner --namespace gitlab-runner --create-namespace -f values.yaml
```

---

## 17. Риски & mitigations

* **Сеть / MetalLB IP pool неправильно задан** → тестируйте пул заранее, держите запас IP.
* **Storage (NFS) slow / inconsistent)** → тест производительности и предусмотреть Longhorn как fallback.
* **Velero не бэкапит PV корректно** → тестовые restores и файл/DB dumps дополнительно.
* **Dev случайно изменил infra** → использовать taints/labels и RBAC; дать dev-ы только namespace права.

---

## 18. Owners / встречи

* **Team Owner:** (вставьте имя) — отвечает за delivery & sign-off.
* **On-call:** (имена) — 1st responder.
* Standup: 15 мин daily (волонтёрский).
* Demo: раз в неделю — показать прогресс и DR тест.

---

## 19. Следующие шаги (немедленно)

1. Записать `OWNERS.md` и распределить ноды.
2. Положить `microk8s-install.sh` в `k8s/install/` и прогнать на чистой ноде.
3. Включить аддоны: dns, ingress, metallb (с пулом), storage; проверить sample app.
4. Установить Velero и сделать первый backup → проверить restore.

---

Если хочешь — могу прямо сейчас:

* сгенерировать `microk8s-install.sh` idempotent скрипт и `join-node.sh` (готовые к копированию);
* собрать `helm` values для `gitlab-runner` и `nfs-subdir-external-provisioner`;
* написать `runbook/restore.md` шаг за шагом (проверенный checklist).

Какие файлы генерируем в первую очередь?
