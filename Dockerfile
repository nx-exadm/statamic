# ==============================================================================
# Stage 1: Build dependencies and compile frontend design assets
# ==============================================================================
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

# Install backend dependencies without optimization first
RUN composer install --no-dev --no-scripts --prefer-dist

# Copy the remaining project codebase
COPY . .

# Run publishing, eliminate the duplicate file, and compile assets together in stage 1
RUN php artisan vendor:publish --provider="Statamic\Eloquent\ServiceProvider" --force \
    && rm -f database/migrations/*_create_entries_table_with_string_ids.php \
    && npm install \
    && npm run build

# Complete final composer optimization dump
RUN composer dump-autoload --no-dev --optimize


# ==============================================================================
# Stage 2: Main Production Web Runtime Engine (Official PHP Apache Image)
# ==============================================================================
FROM php:8.3-apache
WORKDIR /var/www/html

# Install system dependencies, database drivers, and essential design layout engines
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

# Fix Document Root configuration for Laravel/Statamic public directory mapping
RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!/var/www/html/public!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Bring the fully prepared, pre-compiled application package from builder stage
COPY --from=builder /var/www/html /var/www/html

# Ensure safe permissions for the Apache webserver layout
RUN chown -R www-data:www-data /var/www/html

# Copy the entrypoint shell script safely into a system binary location
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# FORCE CLEAN BREAKS: Fixes potential Windows formatting errors (CRLF) on Render Linux systems
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh

# Apply absolute execution permissions to the script
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Hand over container lifecycle to our unified shell entrypoint script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
