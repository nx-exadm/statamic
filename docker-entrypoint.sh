#!/bin/sh
set -e

echo "==> Warming up configuration caches..."
php artisan config:clear
php artisan cache:clear
php artisan config:cache
php artisan route:cache

echo "==> Syncing database schemas..."
php artisan migrate --force

echo "==> Running fail-safe native seeder..."
php artisan tinker --execute="
try {
    \$userRepository = \Statamic\Facades\User::repository();
    \$userExists = \$userRepository->findByEmail('admin@example.com');
    
    if (!\$userExists) {
        \$user = \Statamic\Facades\User::make()
            ->email('admin@example.com')
            ->password('12345678')
            ->name('Admin')
            ->super(true);
            
        \$user->save();
        echo 'Admin created successfully using Statamic Facades!\n';
    } else {
        echo 'Admin already exists, skipping.\n';
    }
} catch (\Throwable \$e) {
    echo 'Seeding skipped: ' . \$e->getMessage() . '\n';
}
"

echo "==> Handing off execution to web process..."
exec "$@"
