# Stage 1: Build dependencies and compile frontend design assets
FROM php:8.3-fpm-alpine AS builder

WORKDIR /var/www/html

# Install system utilities, graphic libraries, and Node.js for compiling assets
RUN apk add --no-cache git unzip bash freetype-dev libjpeg-turbo-dev libpng-dev nodejs npm

# Compile GD extension safely
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd

# Install Composer securely
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy configuration and package manifests first to optimize cache layers
COPY composer.json composer.lock* package.json package-lock.json* vite.config.js ./

# Install backend dependencies without optimizing autoloader yet (avoids discovery errors)
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

# Copy the remaining project codebase
COPY . .

# Run production asset compilation to build CSS and JS files
RUN npm install && npm run build

# Complete composer optimization dump and force package generation
RUN composer dump-autoload --no-dev --optimize


# Stage 2: Main Production Web Runtime Engine (Official PHP Apache Image)
FROM php:8.3-apache

WORKDIR /var/www/html

# Install system dependencies, PostgreSQL support, and layout engines
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

# Bring the compiled vendors, layout styles, and scripts over from Stage 1 workspace
COPY --from=builder /var/www/html /var/www/html

# Ensure safe permissions for the webserver layout
RUN chown -R www-data:www-data /var/www/html

# Run build tasks, schema updates, create super admin, and cache configurations sequentially upon initialization
CMD ["sh", "-c", "php artisan vendor:publish --provider=\"Statamic\\Eloquent\\ServiceProvider\" --force && php artisan migrate --force && if [ -n \"$STATAMIC_ADMIN_EMAIL\" ]; then php artisan statamic:user --email=\"$STATAMIC_ADMIN_EMAIL\" --password=\"$STATAMIC_ADMIN_PASSWORD\" --super --name=\"$STATAMIC_ADMIN_USER\" || true; fi && php artisan config:cache && php artisan route:cache && exec apache2-foreground"]
