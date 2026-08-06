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
    # Natively search for the user through the active Eloquent authentication system
    \$userExists = \Statamic\Facades\User::findByEmail('admin@example.com');
    
    if (!\$userExists) {
        # Call the core Statamic artisan command safely from inside the container runtime
        \Illuminate\Support\Facades\Artisan::call('make:user', [
            '--email' => 'admin@example.com',
            '--password' => '12345678',
            '--name' => 'Admin',
            '--super' => true
        ]);
        echo 'Admin created successfully using make:user!\n';
    } else {
        echo 'Admin already exists, skipping.\n';
    }
} catch (\Throwable \$e) {
    echo 'Seeding skipped: ' . \$e->getMessage() . '\n';
}
"

echo "==> Handing off execution to web process..."
exec "$@"
