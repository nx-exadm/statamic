# Stage 1: Build dependencies
FROM php:8.3-fpm-alpine AS builder

WORKDIR /var/www/html

# Install system utilities and graphic library development packages
RUN apk add --no-cache git unzip bash freetype-dev libjpeg-turbo-dev libpng-dev

# Compile GD extension inside the builder stage to prevent script discovery failures
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd

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


# Stage 2: Main Production Web Runtime Engine (Official PHP Apache Image)
FROM php:8.3-apache

WORKDIR /var/www/html

# Install system dependencies, PostgreSQL support, GD runtime dependencies, and zip
RUN apt-get update && apt-get install -y \
    libpq-dev \
    libzip-dev \
    zip \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_pgsql pdo_mysql zip gd \
    && a2enmod rewrite \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Fix Document Root configuration for Laravel/Statamic public directory
RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!/var/www/html/public!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Bring the vendors and codebase over from the builder stage
COPY --from=builder /var/www/html /var/www/html

# Ensure safe permissions for the webserver layout
RUN chown -R www-data:www-data /var/www/html

# Run build tasks, schema updates, and cache preparation sequentially upon initialization
CMD ["sh", "-c", "php artisan vendor:publish --provider=\"Statamic\\Eloquent\\ServiceProvider\" --tag=statamic-eloquent-migrations --force && php artisan migrate --force && php artisan config:cache && php artisan route:cache && exec apache2-foreground"]
