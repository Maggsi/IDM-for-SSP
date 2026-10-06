#!/bin/sh
# IDM has no background worker — the PHP built-in server IS the whole service.
# (php:8.4-cli ships no php-fpm, so php -S is the web tier; see the KLMS entrypoint
# for the same reasoning.) The router serves existing static files natively and
# forwards everything else to the front controller.
#
# The web server runs in the FOREGROUND: when it exits, the container exits,
# so a dead IDM is never "healthy" while serving nothing.
set -e

# --- First-time schema bootstrap (no-op on subsequent boots) ---
# Same pattern as klms-entrypoint.sh: gate on the marker file
# (/app/var/klms-schema.done, on the SHARED idm-var volume), NOT a table
# count. A "0 tables" check is NOT reliable: the messenger transport can
# auto-create messenger_messages during the php -S boot, so a fresh DB can
# already have 1+ tables and a pure table-count check would skip the
# bootstrap — leaving the real schema missing. The marker is written once,
# after a successful schema:create, and persists in the named volume, so it
# is the reliable "done" signal (wiped together with pgdata on `down -v`).
#
# RACE FIX: the bootstrap is wrapped in flock() on /app/var/klms-schema.lock
# (a SHARED named volume — /tmp is per-container and would not work) plus a
# marker file, so even if two containers of this image ever start on a fresh
# volume, only ONE runs doctrine:schema:create. Idempotent AND race-free.
if [ ! -f /app/var/klms-schema.done ]; then
  echo "First boot: creating database schema (flock: only one container runs it)..."
  flock /app/var/klms-schema.lock -c '
    if [ ! -f /app/var/klms-schema.done ]; then
      php bin/console doctrine:schema:create 2>&1 | grep -vE "deprecation|Deprecated" || true
      touch /app/var/klms-schema.done
    fi
  '
  echo "Schema bootstrap done."
fi

# --- First-run init (idempotent — skip-if-exists) ---
# Creates the IDM API key (value = KLMS_IDM_APIKEY from .env) and the default
# admin user. Both console commands are NOT idempotent (re-run errors), so guard
# with existence checks first: app:apikeys:list / app:user:list. Re-runs
# (container restarts, reboots) are a no-op. Runs AFTER the schema bootstrap so
# the api_key / user tables exist.
if [ -n "${KLMS_IDM_APIKEY:-}" ]; then
  if php bin/console app:apikeys:list 2>/dev/null | grep -qF "${KLMS_IDM_APIKEY}"; then
    echo "First-run init: API key '${KLMS_IDM_APIKEY_NAME:-klms}' already exists — skipping."
  else
    echo "First-run init: creating IDM API key '${KLMS_IDM_APIKEY_NAME:-klms}'..."
    php bin/console app:apikeys:create "${KLMS_IDM_APIKEY_NAME:-klms}" "$KLMS_IDM_APIKEY" 2>&1 | grep -vE 'deprecation|Deprecated' || true
  fi
fi
if [ -n "${KLMS_ADMIN_EMAIL:-}" ] && [ -n "${KLMS_ADMIN_PASSWORD:-}" ]; then
  if php bin/console app:user:list 2>/dev/null | grep -qF "${KLMS_ADMIN_EMAIL}"; then
    echo "First-run init: admin user '${KLMS_ADMIN_EMAIL}' already exists — skipping."
  else
    echo "First-run init: creating default admin user '${KLMS_ADMIN_EMAIL}'..."
    php bin/console app:user:create "$KLMS_ADMIN_EMAIL" "$KLMS_ADMIN_PASSWORD" "${KLMS_ADMIN_NICKNAME:-admin}" --confirmed 2>&1 | grep -vE 'deprecation|Deprecated' || true
  fi
fi

exec php -S 0.0.0.0:8095 -t /app/public /idm-router.php
