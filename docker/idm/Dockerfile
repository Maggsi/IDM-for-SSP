# syntax=docker/dockerfile:1
# Pinned digest (was the floating php:8.4-cli tag) for reproducible builds.
# Re-pin when you intentionally want a newer PHP:
#   podman pull php:8.4-cli && podman image inspect php:8.4-cli --format '{{.Digest}}'
# 8.4.27 = the CVE-2026-109618 / CVE-2026-109619 ("PHP2Shell", CVSS 9.2) fix; the digest it
# replaces (php:8.4-cli@sha256:c4723acd…) was PHP 8.4.26. Deliberately the ONLY
# runtime change on this build: it is cut from the commit prod runs (17b629e), so no
# app-code or composer drift rides along with a security patch.
FROM php:8.4.27-cli@sha256:639f5390cb247618a440a0092bff328e801549fd1ee919b81eaa840a1f2f2a77

# --- system deps for PHP extensions ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev libxml2-dev libicu-dev libonig-dev libzip-dev \
    && docker-php-ext-install pdo_pgsql pgsql xml mbstring intl zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Bake code (vendor/ built at image build time).
# .dockerignore keeps tests/, var/ etc. out of the context.
COPY . .
# Minimal placeholder .env so Dotenv::loadEnv('/app/.env') finds the file.
# (Real values are injected at runtime via compose `environment:`.)
COPY docker/.env.placeholder .env
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts \
    && composer dump-autoload --no-dev \
    && mkdir -p var/cache var/log

# --- non-root runtime user ---
# The PHP process runs as an unprivileged user (uid 1000), not root. The writable
# dir is chowned to it; the runtime named volume inherits this ownership when it
# is first mounted (empty volume -> image content copied in). The first-boot
# schema bootstrap (doctrine:schema:create) writes var/cache as this user.
RUN useradd -m -u 1000 appuser \
    && chown -R appuser:appuser var

EXPOSE 8095

# The PHP built-in server is the web tier (php:8.4-cli ships no php-fpm).
# The router serves existing static files natively (correct MIME + SRI bytes)
# and forwards everything else to the front controller — see docker/idm-router.php.
COPY docker/idm-entrypoint.sh /idm-entrypoint.sh
COPY docker/idm-router.php /idm-router.php
# Cheap in-image DB-reachability probe for the healthchecks (see docker/hcdb.php).
# Mitigation for CVE-2026-109618/109619: session.upload_progress off (see that file).
COPY docker/idm/security.ini /usr/local/etc/php/conf.d/99-security.ini
COPY docker/hcdb.php /hcdb.php
RUN chmod +x /idm-entrypoint.sh

USER appuser
ENTRYPOINT ["/idm-entrypoint.sh"]
