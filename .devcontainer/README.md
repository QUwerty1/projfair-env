# Dev Container для projfair

> Git внутри контейнера не имеет доступа к вашим ключам ssh. Это означает, что если репозиторий был склонирован через ssh `git clone git@github.com:QUwerty1/projfair-env.git`, то для push-а в удаленный репозиторий предется открывть терминал в хост-системе (во встроенном терминале vscode `git push` и `git pull` работать не будут)

После клонирования этого репозитория, необходиимо склонировать репозитории бэкенда и фронтэнда в эту директорию, чтобы в результате структура была такой:
```
projfair
├── .devcontainer
├── .git
├── .gitignore
├── projfair-back
├── projfair-client
└── .vscode
```

## Состав

| Файл | Назначение |
| --- | --- |
| `devcontainer.json` | Точка входа для VS Code / Dev Containers |
| `Dockerfile` | Образ `app`: PHP 8.1 с `pdo_mysql`, `gd`, `zip`, `bcmath`, `intl` |
| `docker-compose.yml` | Сервисы `app`, `db` (MySQL 8.0), `mailhog` |
| `php.ini` | Dev-настройки PHP внутри контейнера |
| `projectfair.sql` | Дамп БД: схема + данные (импортируется вместо `db:seed`) |
| `setup.sh` | Одноразовая инициализация (`postCreateCommand`) |
| `../.vscode/tasks.json` | Задачи VS Code: запуск и проверка всех сервисов |

> Node.js 20 ставится фичей `ghcr.io/devcontainers/features/node`, которая
> применяется **только при открытии проекта через VS Code / Codespaces**.
> При ручном запуске через `docker compose` Node в контейнере не будет —
> `setup.sh` это учитывает и предупреждает вместо падения.

## Как пользоваться

В VS Code: **Dev Containers: Reopen in Container** (или **Rebuild Container**).

Вне VS Code:

```bash
docker compose -p projfair -f .devcontainer/docker-compose.yml up -d --build
docker compose -p projfair -f .devcontainer/docker-compose.yml exec app bash
```

## Что делает `setup.sh`

1. Создаёт `projfair-back/.env` из `.env.example` и проставляет значения под контейнер
   (`DB_HOST=db`, `MAIL_HOST=mailhog`, `APP_DEVELOPMENT=true`).
2. Выполняет `composer install`, генерирует `APP_KEY`, если он пуст.
3. Ждёт готовности MySQL и **импортирует `projectfair.sql`** — пересоздаёт базу
   `projectfair` и заливает дамп.
4. Выполняет `php artisan migrate` — применит только миграции, добавленные в проект
   после выгрузки дампа (в дампе уже есть таблица `migrations` со всеми 65 миграциями,
   поэтому обычно выводится `Nothing to migrate`).
5. Создаёт `projfair-client/.env` с `VITE_API_URL_LOCAL=http://localhost:8000/` и ставит `npm install`.

Скрипт идемпотентен — можно запускать повторно: `.env` бэкенда обновляется,
зависимости ставятся заново, а дамп пропускается, если в базе уже есть таблицы
и проекты. Файл `projfair-client/.env` **отслеживается в git**, поэтому скрипт не
переписывает его целиком: выставляется только `VITE_API_URL_LOCAL`, если он
отсутствует или пуст.

## База данных

БД наполняется **импортом дампа `projectfair.sql`**, а не через `php artisan db:seed`.

Причина: сидеры проекта нерабочие — миграция
`2023_02_15_133327_change_specialities_foreign_key` удаляет `institute_id` у таблицы
`specialities` (заменяя его на `department_id`), а `database/seeders/DatabaseSeeder.php`
всё ещё вставляет `institute_id`, из-за чего `db:seed` падает с
`SQLSTATE[42S22]: Unknown column 'institute_id'`. Это баг проекта, а не конфигурации.

Дамп (phpMyAdmin, MariaDB 10.4, 7,1 МБ) содержит схему и реальные данные:

| Таблица | Записей |
| --- | --- |
| `projects` | 842 |
| `skills` | 415 |
| `specialities` | 97 |
| `departments` | 79 |
| `candidates` | 4273 |
| `supervisors` | 1688 |
| `institutes` | 17 |
| `admin_users` | 2 |
| `migrations` | 67 |

Всего 37 таблиц и 30 внешних ключей — они создаются через `ALTER TABLE` в конце дампа,
поэтому скрипт оборачивает импорт в `SET FOREIGN_KEY_CHECKS=0`.

Особенности дампа, учтённые в `setup.sh`:

- нет `USE` и `CREATE DATABASE` — база указывается при вызове `mysql`;
- нет `DROP TABLE IF EXISTS` — перед импортом база пересоздаётся целиком
  (`DROP DATABASE` + `CREATE DATABASE`), иначе повторный запуск падал бы
  с `Table 'projects' already exists`.

### Переимпорт базы

Если нужно вернуть БД к состоянию дампа (например, после экспериментов):

```bash
docker compose -p projfair -f .devcontainer/docker-compose.yml \
  exec -e PROJFAIR_REIMPORT=1 app bash .devcontainer/setup.sh
```

Либо пересоздать базу целиком вместе с volume — флаг `-v` удаляет и данные MySQL,
после чего нужно заново выполнить `setup.sh`:

```bash
docker compose -p projfair -f .devcontainer/docker-compose.yml down -v
bash .devcontainer/setup.sh
```

## Порты

| Порт | Сервис |
| --- | --- |
| 8000 | `php artisan serve` (API `/api/*` + Swagger UI `/api/documentation`) |
| 3000 | `npm run dev` (Vite) |
| 3306 | MySQL 8.0 (`projectfair` / `root` / `root`) |
| 1025 | SMTP MailHog |
| 8025 | Web-интерфейс MailHog |
| 9003 | Xdebug |

## Что отдаёт порт 8000

Помимо API, `php artisan serve` отдаёт собранную Vue-SPA: в `routes/web.php` в конце
стоит catch-all `Route::get('{page}', fn () => view('index'))->where('page', '.*')`,
который ловит любой GET-путь вне `/api/*` и `/admin/*`. Отсюда:

- `localhost:8000` показывает собранный фронтенд — для разработки фронтенда
  используйте Vite на `localhost:3000`;
- Swagger UI: `/api/documentation`; сырая OpenAPI-схема: `/docs`.

## Задачи VS Code

Все сервисы и частые команды собраны в `.vscode/tasks.json`
(**Terminal → Run Task…**, `Ctrl+Shift+B` — задача по умолчанию):

| Задача | Сервис / порт |
| --- | --- |
| `backend: artisan serve` | Laravel API `:8000` |
| `backend: artisan serve (xdebug)` | то же с `xdebug.mode=debug` |
| `client: vite` / `vite (mock)` | Vite `:3000` / мок-данные |
| `client: storybook` | Storybook `:6006` |
| `db: статус` / `консоль mysql` | MySQL `:3306` |
| `db: переимпорт дампа` / `migrate` | `projectfair` |
| `mailhog: статус` | MailHog `:8025` |
| `lint` / `сборка` | lint |
| `setup: первичная настройка` | `setup.sh` |

Задачи `backend:*`, `client:*`, `db:*`, `mailhog:*` выполняются **внутри** контейнера.
Задачи `compose:*` внутри контейнера **не сработают** — в образе нет docker CLI,
поэтому они выводят подсказку с командой для хоста.

## Запуск

```bash
# Бэкенд — порт обязателен, контейнер обращается к нему снаружи
cd projfair-back && php artisan serve --host=0.0.0.0 --port=8000

# Клиент
cd projfair-client && npm run dev
```

`npm run dev:mock` — фронтенд на мок-данных, без обращения к API.

## Полезно

```bash
composer doc                    # перегенерировать openapi.yaml
./vendor/bin/phpunit            # тесты бэкенда
npm run test:unit               # тесты клиента (vitest)
npm run lint                    # prettier + stylelint + eslint + type-check
```

> `php artisan migrate:fresh --seed` использовать не стоит: сидеры проекта сломаны
> (см. «База данных»), БД наполняется импортом дампа.

### Xdebug

Установлен, но по умолчанию выключен (`xdebug.mode=off`), чтобы не замедлять работу.
Включается на один процесс:

```bash
php -d xdebug.mode=debug artisan serve --host=0.0.0.0 --port=8000
```

Порт отладчика — **9003** (`xdebug.client_port` в `php.ini`, проброшен в compose).
В настройках PHP-расширения VS Code при необходимости добавьте
`"xdebug.defaultPort": 9003`.
