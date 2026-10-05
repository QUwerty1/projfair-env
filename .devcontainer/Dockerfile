# Dev-образ для projfair (Laravel 9 бэкенд + Vue 3 клиент).
# Базовый образ devcontainers уже содержит composer, git, sudo и базовый набор PHP-расширений.
FROM mcr.microsoft.com/devcontainers/php:1-8.1-bookworm

USER root

# В базовом образе объявлен репозиторий yarn (yarn.list), чей GPG-ключ устарел:
# apt-get update падает с "NO_PUBKEY 62D54FD4003F6525" и кодом 100.
# Yarn в проекте не используется (Node ставится фичей devcontainers), поэтому репозиторий убираем.
RUN rm -f /etc/apt/sources.list.d/yarn.list

# Системные пакеты: клиент БД (для отладки), библиотеки для gd/intl/zip, утилиты.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        unzip \
        zip \
        default-mysql-client \
        jq \
        less \
        nano \
        procps \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP-расширения, необходимые проекту (config/database.php -> pdo_mysql, загрузка файлов, gd).
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        pcntl \
        pdo_mysql \
        zip

# Xdebug 3.x уже установлен в базовом образе, но включён в режиме debug
# и стартует на каждый запрос, что замедляет artisan и сыпет
# "Could not connect to debugging client" в лог.
# Отключаем его через php.ini (zz-projfair.ini подключается после xdebug.ini),
# включать можно адресно: php -d xdebug.mode=debug artisan serve

COPY php.ini /usr/local/etc/php/conf.d/zz-projfair.ini

# Каталоги под named volumes: Docker копирует в них владельца из образа,
# иначе кэши composer/npm достались бы пользователю vscode с правами root.
RUN mkdir -p /home/vscode/.cache/composer /home/vscode/.npm \
    && chown -R vscode:vscode /home/vscode/.cache /home/vscode/.npm

USER vscode

WORKDIR /workspaces/projfair
