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
    \$userExists = \DB::table('users')->where('email', 'admin@example.com')->exists();
    if (!\$userExists) {
        \DB::table('users')->insert([
            'name' => 'Admin',
            'email' => 'admin@example.com',
            'password' => \Hash::make('12345678'),
            'data' => json_encode(['super' => true]),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        echo 'Admin created successfully!\n';
    } else {
        echo 'Admin already exists, skipping.\n';
    }
} catch (\Throwable \$e) {
    echo 'Seeding skipped: ' . \$e->getMessage() . '\n';
}
"

echo "==> Handing off execution to web process..."
exec "$@"
