# Docker image for IDM-for-SSP

A self-contained `podman`/`docker` image for the **IDM** (KRRU LAN-Party
Identity Management) fork, as used by the KLMS-for-SSP docker stack. This
repo is the **source of truth for the IDM image build** (`docker/idm/Dockerfile`
+ entrypoint/router); the full-stack `compose.yaml` that orchestrates IDM
together with KLMS, PostgreSQL and nginx lives in
**[Maggsi/KLMS-for-SSP](https://github.com/Maggsi/KLMS-for-SSP) (branch
`main`, file `docker/compose.yaml`, service `idm`)** — that repo's
[`docker/README.md`](https://github.com/Maggsi/KLMS-for-SSP/blob/main/docker/README.md)
documents bringing this image into the stack.

The image runs the Symfony app on the PHP built-in server (`php -S`) on port
**8095** (internal only — the KLMS reaches it over the docker network at
`http://idm:8095`; no host port is published).

## Files

| File                    | Purpose                                                        |
|-------------------------|----------------------------------------------------------------|
| `docker/idm/Dockerfile` | Builds the image (pinned `php:8.4-cli` digest, non-root user). |
| `docker/idm/security.ini` | Pre-patch mitigation for CVE-2026-109618/109619 ("PHP2Shell") — turns off `session.upload_progress`; installed to `/usr/local/etc/php/conf.d/99-security.ini`. |
| `docker/idm-entrypoint.sh` | First-boot schema bootstrap + first-run init, then `php -S`. |
| `docker/idm-router.php` | Router for `php -S` (static files native, else front controller). |
| `docker/.env.placeholder` | Minimal `.env` baked in so `Dotenv::loadEnv` finds a file.  |
| `docker/hcdb.php`       | In-image DB-reachability probe (`SELECT 1`) for healthchecks. |
| `.dockerignore`         | Keeps the build context small (no `node_modules`, `tests/`, …). |

## Build

```bash
# from the repo root (the build context is the repo root)
podman build -f docker/idm/Dockerfile -t klms-dot-idm .
```

The KLMS stack's `compose.yaml` references the pre-built `klms-dot-idm` image
(`image:` instead of `build:`) — `podman-compose` cannot build a service whose
Dockerfile lives outside its own build context.

## How it works

- **Web tier:** `php:8.4-cli` ships no `php-fpm`, so the PHP built-in server
  (`php -S 0.0.0.0:8095 -t /app/public /idm-router.php`) is the web tier. The
  router serves existing static files natively (correct MIME + real bytes, so
  CSS/SRI work) and forwards everything else to the Symfony front controller.
- **Non-root:** the image creates `appuser` (uid 1000) and runs as it; the
  writable dir (`/app/var`) is chowned to it, and the runtime named volume
  (`idm-var`) inherits that ownership on first mount.
- **Schema bootstrap (automatic, race-free):** on first boot the entrypoint
  checks a **marker file** (`/app/var/klms-schema.done`, on the shared `idm-var`
  volume) and, if missing, runs `doctrine:schema:create` (wrapped in `flock()`
  on a lock file so only one container ever does it), then writes the marker.
  A "0 tables" check is deliberately *not* used (the messenger transport can
  auto-create `messenger_messages` during boot). The marker is wiped with the
  volume on `down -v`, so a fresh volume re-bootstraps.
- **First-run init (idempotent):** the entrypoint creates the **IDM API key**
  (value = `KLMS_IDM_APIKEY`) and the **default admin user**
  (`KLMS_ADMIN_EMAIL`/`KLMS_ADMIN_PASSWORD`, `--confirmed`), each guarded by a
  skip-if-exists check (`app:apikeys:list` / `app:user:list`), so re-runs are a
  no-op. The API key value **must match** `KLMS_IDM_APIKEY` in the KLMS `.env` —
  that is the linchpin of KLMS→IDM login.

## Environment (injected at runtime by the KLMS compose `environment:`)

| Var                     | Meaning                                          |
|-------------------------|--------------------------------------------------|
| `APP_ENV`               | Symfony env (`prod`).                             |
| `APP_SECRET`            | Symfony secret.                                   |
| `DATABASE_URL`          | `postgresql://idm_dot:…@postgres:5432/idm_dot`   |
| `KLMS_IDM_APIKEY`       | API key created on first run (match KLMS).       |
| `KLMS_IDM_APIKEY_NAME`  | Name of that key (default `klms`).               |
| `KLMS_ADMIN_EMAIL`      | Default admin email (first-run init).            |
| `KLMS_ADMIN_PASSWORD`   | Default admin password (first-run init).         |
| `KLMS_ADMIN_NICKNAME`   | Default admin nickname (default `admin`).        |
| `SENTRY_DSN` / `MAILER_DSN` | Referenced via `%env(…)%`; present (empty ok). |

The real, secret-bearing `.env` stays on the host (gitignored) and is **not**
baked into the image — only `docker/.env.placeholder` is.

## Healthcheck (defined in the KLMS `compose.yaml`)

`curl -fsS -o /dev/null http://127.0.0.1:8095/ && php /hcdb.php` — proves both
the web tier answers **and** the database is reachable. `start_period: 60s`
covers the slow first boot (`doctrine:schema:create` + Symfony console boot).

## Notes / quirks

- **`php:8.4-cli` base** — the fork's composer lockfile requires PHP ≥ 8.4.
- **`--classmap-authoritative` must NOT be used** for `composer dump-autoload`
  (dev-only bundles are excluded by `--no-dev`; an authoritative classmap would
  break `bin/console` boot).
- **`session.upload_progress` is OFF** (`docker/idm/security.ini`) as a pre-patch
  mitigation for CVE-2026-109618/109619 — see that file for what it does and
  does not cover. It costs nothing here: IDM is a JSON API with no upload
  endpoint. Verify after deploy:
  `docker exec <idm-container> php -i | grep upload_progress.enabled` → `Off`.
- **Web tier:** `php -S` is fine for the LAN/internal service (KLMS reaches it
  on the docker network only; nothing is exposed to the internet). If it ever
  needs to face clients directly, swap to `php-fpm` behind the stack's nginx.
