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

# Bring the fully prepared, pre-compiled application package from builder stage
COPY --from=builder /var/www/html /var/www/html

# Also bring the composer binary itself into the runtime image so diagnostics can use it
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Ensure safe permissions for the webserver layout
RUN chown -R www-data:www-data /var/www/html

# DIAGNOSTIC + FAIL-SAFE RUN
CMD php artisan config:clear && \
    php artisan cache:clear && \
    php artisan migrate --force && \
    echo "===== PACKAGE VERSIONS =====" && \
    composer show statamic/cms statamic/eloquent-driver && \
    echo "===== users.php repository setting =====" && \
    cat config/statamic/users.php | grep -A2 "'repository'" && \
    echo "===== users table columns =====" && \
    php artisan tinker --execute="print_r(\Schema::getColumnListing('users'));" && \
    echo "=============================" && \
    ( php artisan tinker --execute="try { if (!\DB::table('users')->where('email', 'admin@example.com')->exists()) { \Statamic\Facades\User::make()->email('admin@example.com')->password('12345678')->name('Admin')->super(true)->save(); echo 'Admin created successfully!'; } else { echo 'Admin already exists'; } } catch (\Throwable \$e) { echo 'Admin seed skipped: ' . \$e->getMessage(); }" || echo "Admin seed step failed, continuing boot anyway" ) && \
    php artisan config:cache && \
    php artisan route:cache && \
    exec apache2-foreground
