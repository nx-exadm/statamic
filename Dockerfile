# Stage 1: Build dependencies
FROM php:8.3-fpm-alpine AS builder

WORKDIR /var/www/html

# Install system utilities needed for building packages
RUN apk add --no-cache git unzip bash

# Install Composer securely
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy configuration files first to optimize cache layers
COPY composer.json composer.lock* ./

# Install application dependencies safely
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

# Copy the remaining project codebase
COPY . .

# Complete composer optimization dump
RUN composer dump-autoload --no-dev --optimize

# Stage 2: Main Production Web Runtime Engine
FROM serversideup/php:8.3-apache

WORKDIR /var/www/html

# Install system-level PostgreSQL requirements for PHP
USER root
RUN apt-get update && apt-get install -y libpq-dev \
    && docker-php-ext-install pdo_pgsql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Re-assign directory workspace control permissions back to web runner
USER www-data

# Pull complete pre-built vendors directly from Stage 1 workspace layer
COPY --from=builder --chown=www-data:www-data /var/www/html /var/www/html

# Reconfigure environment structural layouts for proper mapping
ENV AUTORUN_ENABLED=true
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

# Run build tasks, schema updates, and cache preparation sequentially upon initialization
CMD ["sh", "-c", "php artisan vendor:publish --provider=\"Statamic\\Eloquent\\ServiceProvider\" --tag=statamic-eloquent-migrations --force && php artisan migrate --force && php artisan config:cache && php artisan route:cache && exec apache2-foreground"]
