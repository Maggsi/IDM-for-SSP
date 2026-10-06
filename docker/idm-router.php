<?php
// Router for the PHP built-in server (see klms-entrypoint.sh).
// Existing static files are served natively by php -S (correct MIME types,
// real bytes — required for CSS to apply and SRI integrity to match).
// Everything else is routed through the Symfony front controller.

$base = '/app/public';
$uri = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH));

if ($uri !== '/' && $uri !== '' && $uri[0] === '/') {
    $file = realpath($base . $uri);
    if ($file !== false && str_starts_with($file, $base . '/') && is_file($file)) {
        return false;
    }
}

require $base . '/index.php';
