# CargoMarket Multisite — Project Context

## Stack
WordPress Multisite + WooCommerce, Docker Compose, deployed on Dokploy VPS with Traefik SSL.
Spec: `docs/superpowers/specs/2026-03-28-cargomarket-multisite-design.md`
Plan: `docs/superpowers/plans/2026-03-28-cargomarket-multisite.md`

## VPS
- Project path: `/etc/dokploy/compose/wpcargomarket-multisite-cargomarket-ufsyas/code`
- **Dokploy wipes the working directory on redeploy** — always `cd` back in before running commands
- After `git pull`, run `sed -i 's/\r//' Makefile` (Windows CRLF → Linux LF)
- `.env` must be created manually on VPS — Dokploy does not create it from `.env.example`

## WP-CLI
- Runs via: `docker run --rm --network cargomarket-internal --volumes-from cargomarket_wordpress --user 33:33 --entrypoint wp -e WP_CLI_CACHE_DIR=/tmp/wp-cli-cache wordpress:cli-php8.3`
- Use `make wp cmd="..."` from the project root — never `docker compose run`
- `wp config set KEY value` (no `--raw`) for strings — `--raw` writes a bare PHP constant, not a string

## Docker / MariaDB
- MariaDB 10.11 requires `MARIADB_ROOT_PASSWORD` (not just `MYSQL_ROOT_PASSWORD`) for fresh init
- Internal network has fixed name: `cargomarket-internal`
- Container names: `cargomarket_wordpress`, `cargomarket_db`, `cargomarket_redis`

## Domains (Dokploy)
- Add both `aistaffing.ae` and `www.aistaffing.ae` in Dokploy → Domains tab, port 80, HTTPS on
- After any domain change, redeploy the compose stack to apply Traefik labels
- Primary network admin URL: `https://aistaffing.ae/wp-admin/network/`

## Adding a New Store
See `docs/add-new-site.md` — summary: `make add-site slug=X title="Y" email=Z domain=D`
Then add the domain in Dokploy → redeploy.
