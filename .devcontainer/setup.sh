#!/usr/bin/env bash
# Первичная настройка рабочего окружения projfair.
# Выполняется один раз при создании контейнера (postCreateCommand).
# Идемпотентен: повторный запуск безопасен и ничего не ломает.
#
# Базу данных заполняет сам сервис db: при первом создании тома он импортирует
# .devcontainer/projectfair.sql (сидеры проекта нерабочие), а compose запускает
# app только после этого (depends_on: service_healthy).
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
BACK="$WORKSPACE/projfair-back"
CLIENT="$WORKSPACE/projfair-client"
NPM_LOG="$WORKSPACE/.devcontainer/tmp/npm-install.log"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# Репозитории бэкенда и клиента на Windows могут быть склонированы с CRLF:
# тогда пустой APP_KEY читается как "\r" и проверки ниже срабатывают неверно.
to_lf() { sed -i 's/\r$//' "$1"; }

# Заменяет или дописывает KEY=VALUE в .env
set_env() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
}

# На Windows файлы смонтированы от root, а работаем мы под vscode: git отказывается
# работать с такими репозиториями ("detected dubious ownership"). VS Code добавляет
# в safe.directory только папку рабочей области, а бэкенд и клиент — отдельные репозитории.
for repo in "$WORKSPACE" "$BACK" "$CLIENT"; do
    if [ "$(stat -c %u "$repo")" != "$(id -u)" ] \
        && ! git config --global --get-all safe.directory | grep -qxF "$repo"; then
        git config --global --add safe.directory "$repo"
        echo "git: $repo добавлен в safe.directory"
    fi
done

# ---------------------------------------------------------------- клиент ---
# npm install не зависит от бэкенда, поэтому запускаем его параллельно
# с composer install; вывод — в лог, чтобы не смешивался с выводом composer.
log "Клиент: npm install (в фоне, лог: ${NPM_LOG#"$WORKSPACE"/})"
mkdir -p "$(dirname "$NPM_LOG")"
(cd "$CLIENT" && npm install --no-fund --no-audit) >"$NPM_LOG" 2>&1 &
npm_pid=$!

# ---------------------------------------------------------------- бэкенд ---
log "Бэкенд (Laravel 9): .env"
cd "$BACK"
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Создан .env из .env.example"
else
    echo ".env уже существует, обновляю только значения для контейнера"
fi
to_lf .env

# Только то, что отличается от .env.example; остальные значения
# (APP_DEVELOPMENT=true для мок-авторизации, драйверы, MAIL_PORT и т.д.) там уже подходят.
set_env .env APP_NAME     "Projectfair"
set_env .env APP_URL      "http://localhost:8000"
set_env .env DB_HOST      "db"
set_env .env DB_PASSWORD  "root"
set_env .env MAIL_HOST    "mailpit"

log "Бэкенд: composer install"
composer install --no-interaction --prefer-dist

if [ -z "$(grep -E '^APP_KEY=' .env | cut -d= -f2-)" ]; then
    log "Бэкенд: генерация APP_KEY"
    php artisan key:generate --ansi
fi

# Каталоги Laravel должны быть writable. Меняем права только у каталогов:
# chmod -R затрагивает и файлы, из-за чего git видит изменение mode
# у отслеживаемых storage/**/.gitignore и storage/api-docs/api-docs.json.
# Трогаем лишь недоступные для записи: на Windows (Docker Desktop) файлы
# смонтированы от root с правами 777, и chmod там падает с "Operation not permitted".
find storage bootstrap/cache -type d ! -writable -exec chmod ug+rwx {} + \
    || warn "Не удалось выдать права на storage/ и bootstrap/cache/ — Laravel не сможет писать кэш и логи"

# Дамп уже содержит таблицу `migrations` со всеми миграциями проекта,
# поэтому migrate применит только миграции, добавленные после выгрузки дампа.
log "Бэкенд: миграции"
php artisan migrate --force --ansi

# ---------------------------------------------------------------- клиент ---
log "Клиент (Vue 3 + Vite): .env"
cd "$CLIENT"

# .env клиента отслеживается в git, поэтому не переписываем его целиком:
# проставляем только VITE_API_URL_LOCAL и то лишь если ключа нет или он пуст.
# VITE_MOCK_API намеренно не трогаем — это выбор проекта.
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Создан .env из .env.example"
fi
to_lf .env

if grep -qE '^VITE_API_URL_LOCAL=.+' .env; then
    echo "VITE_API_URL_LOCAL уже задан, оставляю как есть"
else
    set_env .env VITE_API_URL_LOCAL "http://localhost:8000/"
    echo "VITE_API_URL_LOCAL -> http://localhost:8000/"
fi

log "Клиент: ожидание npm install"
if ! wait "$npm_pid"; then
    tail -n 40 "$NPM_LOG"
    warn "npm install завершился с ошибкой, полный лог: $NPM_LOG"
    exit 1
fi
tail -n 3 "$NPM_LOG"

cat <<'BANNER'

  projfair готов к работе.

    API (Laravel):     http://localhost:8000
    Swagger UI:        http://localhost:8000/api/documentation
    Клиент (Vite):     http://localhost:3000
    Mailpit UI:        http://localhost:8025

  Готовые задачи — в .vscode/tasks.json (Terminal -> Run Task...).

    cd projfair-back   && php artisan serve --host=0.0.0.0 --port=8000
    cd projfair-client && npm run dev

BANNER
