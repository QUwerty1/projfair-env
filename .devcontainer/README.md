# Dev Container для projfair

> Git внутри контейнера не имеет доступа к вашим ключам ssh. Это означает, что если репозиторий был склонирован через ssh `git clone git@github.com:QUwerty1/projfair-env.git`, то для push-а в удаленный репозиторий придется открывать терминал в хост-системе (во встроенном терминале vscode `git push` и `git pull` работать не будут)

После клонирования этого репозитория, необходимо склонировать репозитории бэкенда и фронтэнда в эту директорию, чтобы в результате структура была такой:

```
projfair
├── .devcontainer
├── .git
├── .gitignore
├── projfair-back
├── projfair-client
└── .vscode
```

> Windows: скрипты выполняются в Linux-контейнере, поэтому `.gitattributes` фиксирует окончания строк LF. Если репозиторий был склонирован раньше и `setup.sh` падает с `$'\r': command not found`, перевыгрузите рабочую копию (несохранённые изменения пропадут): `git rm --cached -r . -q && git reset --hard`

## Порты

| Порт | Сервис |
| --- | --- |
| 8000 | `php artisan serve` |
| 3000 | `npm run dev` (Vite) |
| 3306 | MySQL 8.0 (`projectfair` / `root` / `root`) |
| 1025 | SMTP Mailpit |
| 8025 | Web-интерфейс Mailpit |

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
| `mailpit: статус` | Mailpit `:8025` |
| `lint` / `сборка` | lint |
| `setup: первичная настройка` | `setup.sh` |

## Запуск

```bash
# Бэкенд — порт обязателен, контейнер обращается к нему снаружи
cd projfair-back && php artisan serve --host=0.0.0.0 --port=8000

# Клиент
cd projfair-client && npm run dev

# Клиент на мок-данных, без обращения к API
cd projfair-client && npm run dev:mock
```

## Полезно

```bash
composer doc                    # перегенерировать openapi.yaml
./vendor/bin/phpunit            # тесты бэкенда
npm run test:unit               # тесты клиента (vitest)
npm run lint                    # prettier + stylelint + eslint + type-check
```

### Xdebug

Установлен, но по умолчанию выключен (`xdebug.mode=off`), чтобы не замедлять работу.
Включается на один процесс:

```bash
php -d xdebug.mode=debug artisan serve --host=0.0.0.0 --port=8000
```

Отладчик (расширение PHP Debug) работает внутри контейнера и слушает порт **9003**
(`xdebug.client_port` в `php.ini`), наружу порт не публикуется. Запустите
конфигурацию **Listen for Xdebug** (F5), затем задачу `backend: artisan serve (xdebug)`.

### База данных

Сервис `db` импортирует `projectfair.sql` сам, при первом создании тома `db-data`.
Вернуть базу к состоянию дампа — задача `db: переимпорт дампа` или с хоста:

```bash
docker compose -p projfair -f .devcontainer/docker-compose.yml down -v
```
