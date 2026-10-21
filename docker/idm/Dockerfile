# syntax=docker/dockerfile:1
# Pinned digest (was the floating php:8.4-cli tag) for reproducible builds.
#
# 8.4.27 is the CVE-2026-109618 / CVE-2026-109619 ("PHP2Shell", CVSS 9.2) fix; the
# digest this replaces (php:8.4-cli@sha256:c4723acd…) was PHP 8.4.26. The tag name
# moved from the floating `php:8.4-cli` to the explicit `php:8.4.27-cli`, so a future
# upstream 8.4.28 rebuild will NOT silently move this build under us. IDM is
# internal-only, but it shares the digest with KLMS — patch both or neither.
# docker/idm/security.ini stays in place on purpose (PHP recommends keeping
# session.upload_progress off even on a patched runtime).
#
# Re-pin when you intentionally want a newer PHP:
#   skopeo inspect --override-os linux --override-arch amd64 \
#       --format '{{.Digest}}' docker://php:8.4.28-cli
# Use skopeo, not `curl` against the Hub tag API: a tag returns HTTP 200 while its
# OCI index is still empty mid-push (that happened with this very release at 15:40
# UTC), and `8.4.xRC1` tags sit on the registry for weeks before any final release.
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
# See docker/klms/Dockerfile: composer >=2.10 as root without
# COMPOSER_ALLOW_SUPERUSER disables plugins -> missing vendor/autoload_runtime.php.
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts \
    && composer dump-autoload --no-dev \
    && test -f vendor/autoload_runtime.php \
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
# Pre-patch mitigation for CVE-2026-109618/109619 ("PHP2Shell"): turns off
# session upload progress - see docker/idm/security.ini for what it does and
# what it does NOT do.
COPY docker/idm/security.ini /usr/local/etc/php/conf.d/99-security.ini
# Cheap in-image DB-reachability probe for the healthchecks (see docker/hcdb.php).
COPY docker/hcdb.php /hcdb.php
RUN chmod +x /idm-entrypoint.sh

USER appuser
ENTRYPOINT ["/idm-entrypoint.sh"]
