#!/usr/bin/env bash
# Первичная настройка рабочего окружения projfair.
# Выполняется один раз при создании контейнера (postCreateCommand).
# Идемпотентен: повторный запуск безопасен и ничего не ломает.
set -euo pipefail

WORKSPACE="/workspaces/projfair"
BACK="$WORKSPACE/projfair-back"
CLIENT="$WORKSPACE/projfair-client"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# Заменяет или дописывает KEY=VALUE в .env
set_env() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
}

wait_for_mysql() {
    log "Ожидание готовности MySQL"
    for _ in $(seq 1 60); do
        if php -r 'try { new PDO("mysql:host=" . getenv("DB_HOST"), "root", "root"); exit(0); } catch (Throwable $e) { exit(1); }'; then
            echo "MySQL доступен"
            return 0
        fi
        sleep 2
    done
    warn "MySQL не ответил за отведённое время, продолжаю без импорта дампа"
    return 1
}

# Импорт .devcontainer/projectfair.sql вместо `php artisan db:seed`:
# сидеры проекта нерабочие, а дамп содержит схему и реальные данные
# (842 проекта, 415 навыков, справочники, админка) плюс таблицу `migrations`.
#
# Дамп сделан phpMyAdmin и не содержит ни `USE`, ни `DROP TABLE IF EXISTS`,
# поэтому базу пересоздаём целиком — иначе повторный запуск упадёт
# с "Table 'projects' already exists".
import_sql_dump() {
    local dump="$WORKSPACE/.devcontainer/projectfair.sql"
    local db="projectfair"
    local mysql=(mysql -h db -P 3306 -u root -proot --default-character-set=utf8mb4)

    if [ ! -f "$dump" ]; then
        warn "Файл дампа не найден: $dump — база останется без данных (миграции её создадут)"
        return 0
    fi

    # Считаем дамп импортированным, только если есть и схема, и данные:
    # таблица `migrations` сама по себе ещё ничего не значит — её создаёт
    # и `php artisan migrate`, который мог отработать раньше импорта.
    local tables projects
    tables=$("${mysql[@]}" -N -B -e \
        "SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = '$db' AND table_name = 'migrations';" 2>/dev/null || echo 0)
    projects=$("${mysql[@]}" -N -B -e \
        "SELECT COUNT(*) FROM \`$db\`.\`projects\`;" 2>/dev/null || echo 0)

    if [ "${tables:-0}" -gt 0 ] && [ "${projects:-0}" -gt 0 ] && [ -z "${PROJFAIR_REIMPORT:-}" ]; then
        log "Бэкенд: дамп уже импортирован (проектов: $projects), пропускаю"
        echo "Принудительный переимпорт: PROJFAIR_REIMPORT=1 bash .devcontainer/setup.sh"
        return 0
    fi

    log "Бэкенд: импорт projectfair.sql ($(du -h "$dump" | cut -f1))"

    # Пересоздаём базу, чтобы импорт был повторяемым.
    "${mysql[@]}" -e "DROP DATABASE IF EXISTS \`$db\`;
                      CREATE DATABASE \`$db\`
                      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    # Дамп не отключает проверку внешних ключей и добавляет их через ALTER TABLE
    # в конце, поэтому на время импорта отключаем её.
    {
        printf 'SET FOREIGN_KEY_CHECKS=0;\n'
        cat "$dump"
        printf '\nSET FOREIGN_KEY_CHECKS=1;\n'
    } | "${mysql[@]}" "$db"

    tables=$("${mysql[@]}" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';")
    projects=$("${mysql[@]}" -N -B -e "SELECT COUNT(*) FROM \`$db\`.\`projects\`;" 2>/dev/null || echo 0)

    echo "Импортировано таблиц: $tables, проектов: $projects"

    if [ "$tables" -lt 30 ] || [ "${projects:-0}" -eq 0 ]; then
        warn "Импорт выглядит неполным (таблиц: $tables, проектов: $projects) — проверьте дамп"
        return 1
    fi
}

# ---------------------------------------------------------------- бэкенд ---
log "Бэкенд (Laravel 9): .env"
cd "$BACK"
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Создан .env из .env.example"
else
    echo ".env уже существует, обновляю только значения для контейнера"
fi

set_env .env APP_NAME            "Projectfair"
set_env .env APP_ENV             "local"
set_env .env APP_DEBUG           "true"
# Включает мок-авторизацию через кампус (app/Http/Controllers/Campus/LoginController.php)
set_env .env APP_DEVELOPMENT     "true"
set_env .env APP_URL             "http://localhost:8000"
set_env .env DB_CONNECTION       "mysql"
set_env .env DB_HOST             "db"
set_env .env DB_PORT             "3306"
set_env .env DB_DATABASE         "projectfair"
set_env .env DB_USERNAME         "root"
set_env .env DB_PASSWORD         "root"
set_env .env CACHE_DRIVER        "file"
set_env .env SESSION_DRIVER      "file"
set_env .env QUEUE_CONNECTION    "sync"
set_env .env BROADCAST_DRIVER    "log"
set_env .env FILESYSTEM_DISK     "local"
set_env .env MAIL_MAILER         "smtp"
set_env .env MAIL_HOST           "mailhog"
set_env .env MAIL_PORT           "1025"
set_env .env MAIL_USERNAME       "null"
set_env .env MAIL_PASSWORD       "null"
set_env .env MAIL_ENCRYPTION     "null"

log "Бэкенд: composer install"
composer install --no-interaction --prefer-dist

if [ -z "$(grep -E '^APP_KEY=' .env | cut -d= -f2-)" ]; then
    log "Бэкенд: генерация APP_KEY"
    php artisan key:generate --ansi
fi

# Каталоги Laravel должны быть writable. Меняем права только у каталогов:
# chmod -R затрагивает и файлы, из-за чего git видит изменение mode
# у отслеживаемых storage/**/.gitignore и storage/api-docs/api-docs.json.
find storage bootstrap/cache -type d -exec chmod ug+rwx {} +

if wait_for_mysql; then
    import_sql_dump
    # Дамп уже содержит таблицу `migrations` со всеми миграциями проекта,
    # поэтому migrate отработает вхолостую и применит только новые миграции,
    # добавленные в проект после выгрузки дампа.
    log "Бэкенд: миграции"
    php artisan migrate --force --ansi
else
    warn "Пропускаю импорт дампа: БД недоступна."
    warn "Запустите позже: bash .devcontainer/setup.sh"
fi

# ---------------------------------------------------------------- клиент ---
log "Клиент (Vue 3 + Vite)"
cd "$CLIENT"

# .env клиента отслеживается в git, поэтому не переписываем его целиком:
# проставляем только VITE_API_URL_LOCAL и то лишь если ключа нет или он ведёт
# на другой хост. VITE_MOCK_API намеренно не трогаем — это выбор проекта.
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Создан .env из .env.example"
fi

if ! grep -q '^VITE_API_URL_LOCAL=' .env || grep -qE '^VITE_API_URL_LOCAL=(http://localhost:8000/)?$' .env; then
    set_env .env VITE_API_URL_LOCAL "http://localhost:8000/"
    echo "VITE_API_URL_LOCAL -> http://localhost:8000/"
else
    echo "VITE_API_URL_LOCAL уже задан, оставляю как есть"
fi

# Node ставится фичей devcontainer, которая применяется только при открытии
# проекта через VS Code / Codespaces. При обычном docker compose запуске
# npm может отсутствовать — это не повод валить настройку.
if command -v npm >/dev/null 2>&1; then
    log "Клиент: npm install"
    npm install --no-fund --no-audit
else
    warn "npm не найден в контейнере: откройте проект через Dev Containers (фича Node 20) или выполните npm install вручную"
fi

cat <<'BANNER'

  projfair готов к работе.

    API (Laravel):     http://localhost:8000
    Swagger UI:        http://localhost:8000/api/documentation
    Клиент (Vite):     http://localhost:3000
    MailHog UI:        http://localhost:8025

  Терминалы в VS Code уже открыты в projfair-back и projfair-client.
  Готовые задачи — в .vscode/tasks.json (Terminal -> Run Task...).

    cd projfair-back   && php artisan serve --host=0.0.0.0 --port=8000
    cd projfair-client && npm run dev

BANNER
