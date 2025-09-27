
# 🚀 GitLab Docker Setup

Этот проект содержит bash-скрипт для автоматической подготовки и запуска **GitLab Community Edition** в Docker с использованием PostgreSQL и Redis.

## 📌 Возможности

- Генерация случайных паролей для всех сервисов.
- Автоматическое создание файлов:

-`.env` – переменные окружения.

-`config.rb` – конфигурация GitLab.

-`docker-compose.yml` – стек GitLab + PostgreSQL + Redis.

- Старт контейнеров через **Docker Compose**.
- Вывод сгенерированных учётных данных для root-пользователя.

## 🛠 Требования

- Linux / macOS

-[Docker](https://docs.docker.com/get-docker/)

-[Docker Compose](https://docs.docker.com/compose/install/)

-`bash` (скрипт использует `set -euo pipefail`)

- Установленный `tput` (обычно есть по умолчанию в `ncurses`).

## ⚡ Установка и запуск

1. Клонируй репозиторий:

```bash

git clone <repo-url>

cd <repo-name>/gitlab

```

2. Запусти скрипт:

```bash

./run.sh

```

3. Скрипт выполнит следующие шаги:

- Подготовит рабочую директорию `gitlab/`
- Сгенерирует пароли и сохранит их в `.env`
- Создаст `config.rb` и `docker-compose.yml`
- Запустит GitLab стек
- Выведет логин и пароль root-пользователя

## 🔑 Доступ к GitLab

- URL: [http://git.dev.box](http://git.dev.box)
- Root Email: `root@anykey.pro`
- Root Password: будет сгенерирован автоматически и показан в конце выполнения скрипта.

## 📂 Структура проекта

```

.

├── run.sh       # основной скрипт

└── gitlab/

    ├── .env              # переменные окружения

    ├── config.rb         # конфигурация GitLab

    └── docker-compose.yml# docker-compose стек

```

## 🧹 Управление контейнерами

Остановить:

```bash

docker compose down

```

Перезапустить:

```bash

docker compose up -d

```

Просмотр логов:

```bash

docker compose logs -f

```

## ⚠️ Замечания

- По умолчанию GitLab доступен по `http://git.dev.box`. Убедись, что этот домен прописан в `/etc/hosts`:

```

  127.0.0.1 git.dev.box

```
