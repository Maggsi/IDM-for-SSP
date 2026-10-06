<?php
// Cheap in-image DB-reachability probe for the container healthchecks.
// Reads DATABASE_URL (the app uses the postgresql:// scheme), builds a PDO
// pgsql DSN, and runs SELECT 1. Exit 0 = reachable, non-zero = unreachable.
// Catches a ZOMBIE worker (process alive but DB unreachable). Uses only the
// pdo_pgsql the image already ships — no new deps.
//
// NOTE: this is a FILE (not an inline `php -r`) on purpose. podman-compose
// interpolates bare $VAR in the compose healthcheck string (a bare $p/$ok
// would be replaced with the env value or empty, breaking the probe). Keeping
// the $ in a baked file sidesteps that interpolation.
$u = getenv("DATABASE_URL");
if ($u === false) {
    exit(1);
}
$p = parse_url($u);
if ($p === false || !isset($p["host"])) {
    exit(1);
}
$db = ltrim($p["path"] ?? "", "/");
$d = "pgsql:host=" . $p["host"] . ";port=" . ($p["port"] ?? 5432) . ";dbname=" . $db;
if (isset($p["user"])) {
    $d .= ";user=" . $p["user"];
}
if (isset($p["pass"])) {
    $d .= ";password=" . $p["pass"];
}
try {
    $pdo = new PDO($d);
    $pdo->query("SELECT 1");
    exit(0);
} catch (PDOException $e) {
    exit(1);
}
