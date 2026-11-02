# Dev-образ для projfair (Laravel 9 бэкенд + Vue 3 клиент).
# Базовый образ devcontainers уже содержит composer, git, sudo и базовый набор PHP-расширений.
FROM mcr.microsoft.com/devcontainers/php:1-8.1-bookworm

# В базовом образе объявлен репозиторий yarn (yarn.list), чей GPG-ключ устарел:
# apt-get update падает с "NO_PUBKEY 62D54FD4003F6525" и кодом 100.
# Yarn в проекте не используется, поэтому репозиторий убираем.
RUN rm -f /etc/apt/sources.list.d/yarn.list

# PHP-расширения, необходимые проекту (config/database.php -> pdo_mysql, загрузка файлов, gd).
# -dev пакеты нужны только для компиляции: после неё удаляем их, оставляя
# лишь runtime-библиотеки, от которых зависят собранные .so (приём из официального образа php).
RUN savedAptMark="$(apt-mark showmanual)" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libicu-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        pdo_mysql \
        zip \
    && apt-mark auto '.*' >/dev/null \
    && apt-mark manual $savedAptMark >/dev/null \
    && find /usr/local -type f -executable -exec ldd '{}' ';' 2>/dev/null \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search 2>/dev/null \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual >/dev/null \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/*

# Клиент БД для отладки; zip/unzip, jq, less, nano, procps уже есть в базовом образе.
RUN apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Node 20 прямо в образе (а не фичей devcontainers), чтобы npm был доступен
# и при запуске через `docker compose` без VS Code.
COPY --from=node:20-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:20-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# Каталоги под named volumes: Docker копирует в них владельца из образа,
# иначе кэши composer/npm достались бы пользователю vscode с правами root.
RUN mkdir -p /home/vscode/.composer/cache /home/vscode/.npm \
    && chown -R vscode:vscode /home/vscode/.composer /home/vscode/.npm

USER vscode

WORKDIR /workspaces/projfair
