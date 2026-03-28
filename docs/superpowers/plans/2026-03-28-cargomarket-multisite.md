# CargoMarket Multisite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a Docker Compose WordPress Multisite + WooCommerce stack on an existing Dokploy VPS with per-site custom domains and automatic SSL.

**Architecture:** Single `docker-compose.yml` with three services (WordPress, MariaDB, Redis) on a shared internal network plus Dokploy's external Traefik network. A custom `sunrise.php` dropin handles domain mapping from `wp_blogs`. WordPress configuration is split into two phases: single-site install first, then multisite network activation.

**Tech Stack:** WordPress 6.7 / PHP 8.3 / Apache, MariaDB 10.11, Redis 7 Alpine, WP-CLI (wordpress:cli image), Docker Compose, Dokploy + Traefik, WooCommerce, Redis Cache plugin

---

## File Map

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All services, volumes, networks, Traefik labels |
| `.env` | Runtime secrets — never committed |
| `.env.example` | Template committed to git |
| `.gitignore` | Excludes .env, uploads, compiled assets |
| `Makefile` | Shortcuts: `wp`, `add-site`, `backup-db`, `restore-db` |
| `config/php.ini` | PHP memory + opcache tuning |
| `config/uploads.ini` | PHP upload size limits |
| `config/mariadb.cnf` | InnoDB buffer + connection tuning |
| `config/wp-extra.php` | WordPress constants (mounted into container) — **edited twice**: Phase 1 (single-site) → Phase 2 (multisite) |
| `wp-content/sunrise.php` | Custom domain-mapping dropin, reads `wp_blogs.domain` |
| `wp-content/mu-plugins/.gitkeep` | Keeps mu-plugins dir in git |
| `wp-content/plugins/.gitkeep` | Keeps plugins dir in git |
| `wp-content/themes/.gitkeep` | Keeps themes dir in git |
| `backups/.gitkeep` | DB dump destination |
| `docs/add-new-site.md` | Per-store provisioning runbook |

---

## Task 1: Project Scaffold

**Files:**
- Create: `.gitignore`
- Create: `.env.example`
- Create: `backups/.gitkeep`
- Create: `wp-content/mu-plugins/.gitkeep`
- Create: `wp-content/plugins/.gitkeep`
- Create: `wp-content/themes/.gitkeep`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Secrets
.env

# WordPress uploads
wp-content/uploads/

# Database dumps (keep backups/ dir, not contents)
backups/*.sql
backups/*.sql.gz

# OS / editor
.DS_Store
Thumbs.db
.idea/
.vscode/

# Superpowers brainstorm sessions
.superpowers/
```

- [ ] **Step 2: Create `.env.example`**

```env
# ── MariaDB ──────────────────────────────────────────────────────
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=change_me_strong_password
MYSQL_ROOT_PASSWORD=change_me_root_password

# ── WordPress Network ─────────────────────────────────────────────
# Primary domain for Network Admin (must already point to this VPS)
NETWORK_DOMAIN=network.cargomarket.com

# ── WordPress Salts ───────────────────────────────────────────────
# Generate fresh values at: https://api.wordpress.org/secret-key/1.1/salt/
WORDPRESS_AUTH_KEY=put-your-unique-phrase-here
WORDPRESS_SECURE_AUTH_KEY=put-your-unique-phrase-here
WORDPRESS_LOGGED_IN_KEY=put-your-unique-phrase-here
WORDPRESS_NONCE_KEY=put-your-unique-phrase-here
WORDPRESS_AUTH_SALT=put-your-unique-phrase-here
WORDPRESS_SECURE_AUTH_SALT=put-your-unique-phrase-here
WORDPRESS_LOGGED_IN_SALT=put-your-unique-phrase-here
WORDPRESS_NONCE_SALT=put-your-unique-phrase-here
```

- [ ] **Step 3: Create placeholder files to track empty directories**

```bash
touch backups/.gitkeep
touch wp-content/mu-plugins/.gitkeep
touch wp-content/plugins/.gitkeep
touch wp-content/themes/.gitkeep
```

- [ ] **Step 4: Verify structure**

```bash
find . -name ".gitkeep" | sort
```

Expected output:
```
./backups/.gitkeep
./wp-content/mu-plugins/.gitkeep
./wp-content/plugins/.gitkeep
./wp-content/themes/.gitkeep
```

---

## Task 2: PHP Configuration Files

**Files:**
- Create: `config/uploads.ini`
- Create: `config/php.ini`

- [ ] **Step 1: Create `config/uploads.ini`**

```ini
; PHP upload limit overrides for WordPress media uploads
file_uploads = On
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
```

- [ ] **Step 2: Create `config/php.ini`**

```ini
; PHP performance tuning for WordPress + WooCommerce

; Memory
memory_limit = 256M

; OPcache (significant performance boost for WooCommerce)
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1

; Session
session.gc_maxlifetime = 3600
```

- [ ] **Step 3: Verify files exist**

```bash
ls -la config/
```

Expected:
```
uploads.ini
php.ini
```

---

## Task 3: MariaDB Configuration

**Files:**
- Create: `config/mariadb.cnf`

- [ ] **Step 1: Create `config/mariadb.cnf`**

```ini
[mysqld]
# InnoDB buffer pool — set to ~50% of available RAM on the VPS
# Adjust down if VPS has less than 2 GB RAM
innodb_buffer_pool_size = 512M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Connections — supports 6-20 WooCommerce sites
max_connections = 200
max_allowed_packet = 64M

# Query cache (disabled in MariaDB 10.1.7+ by default — keep off)
query_cache_type = 0
query_cache_size = 0

# Charset
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
```

- [ ] **Step 2: Verify**

```bash
cat config/mariadb.cnf | grep innodb_buffer_pool_size
```

Expected: `innodb_buffer_pool_size = 512M`

---

## Task 4: WordPress Config + Domain Mapping Dropin

**Files:**
- Create: `config/wp-extra.php` (Phase 1 — single-site mode)
- Create: `wp-content/sunrise.php`

- [ ] **Step 1: Create `config/wp-extra.php` (Phase 1 — no MULTISITE yet)**

```php
<?php
/**
 * wp-extra.php — Phase 1 (single-site install)
 * Mounted into the container at /var/www/html/wp-extra.php
 * DO NOT define MULTISITE here until after `wp core multisite-install` runs.
 */

// Allow multisite to be enabled via WP Admin / WP-CLI
define( 'WP_ALLOW_MULTISITE', true );

// Redis object cache
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );

// Memory limits
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Disable file editing in WP Admin (security)
define( 'DISALLOW_FILE_EDIT', true );
```

- [ ] **Step 2: Create `wp-content/sunrise.php` (domain mapping dropin)**

```php
<?php
/**
 * sunrise.php — Custom domain mapping for WordPress Multisite
 *
 * WordPress loads this file early in bootstrap (wp-settings.php) when
 * define('SUNRISE', 'on') is present in wp-config.php.
 *
 * Maps incoming HTTP host → correct site in wp_blogs.domain column.
 * No external plugin required — uses WordPress core's own table.
 */

defined( 'SUNRISE' ) || exit;

global $wpdb, $current_blog;

// Normalise the incoming host: strip port and leading www.
$_sm_host   = isset( $_SERVER['HTTP_HOST'] ) ? strtolower( $_SERVER['HTTP_HOST'] ) : '';
$_sm_host   = preg_replace( '/:\d+$/', '', $_sm_host );          // strip :port
$_sm_domain = preg_replace( '/^www\./i', '', $_sm_host );        // strip www.

// No custom mapping needed for the primary network domain.
if ( $_sm_domain === DOMAIN_CURRENT_SITE || $_sm_host === DOMAIN_CURRENT_SITE ) {
    unset( $_sm_host, $_sm_domain );
    return;
}

// Look up by bare domain first, then www. variant.
$_sm_blog = $wpdb->get_row(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->blogs}
         WHERE domain = %s AND deleted = 0 AND archived = '0'
         LIMIT 1",
        $_sm_domain
    )
);

if ( ! $_sm_blog ) {
    $_sm_blog = $wpdb->get_row(
        $wpdb->prepare(
            "SELECT * FROM {$wpdb->blogs}
             WHERE domain = %s AND deleted = 0 AND archived = '0'
             LIMIT 1",
            'www.' . $_sm_domain
        )
    );
}

if ( ! $_sm_blog ) {
    unset( $_sm_host, $_sm_domain, $_sm_blog );
    return;
}

// Apply the mapping.
$current_blog          = $_sm_blog;
$current_blog->site_id = 1;

if ( ! defined( 'COOKIE_DOMAIN' ) ) {
    define( 'COOKIE_DOMAIN', $_sm_domain );
}

// Force HTTPS URLs for the mapped domain.
define( 'WP_SITEURL', 'https://' . $_sm_domain );
define( 'WP_HOME',    'https://' . $_sm_domain );

unset( $_sm_host, $_sm_domain, $_sm_blog );
```

- [ ] **Step 3: Verify both files exist**

```bash
ls config/wp-extra.php wp-content/sunrise.php
```

Expected: both paths echo back without error.

---

## Task 5: Docker Compose File

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `docker-compose.yml`**

```yaml
services:

  # ── WordPress Multisite + WooCommerce ────────────────────────────
  wordpress:
    image: wordpress:6.7-php8.3-apache
    container_name: cargomarket_wordpress
    restart: unless-stopped
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_TABLE_PREFIX: wp_
      NETWORK_DOMAIN: ${NETWORK_DOMAIN}
      # Salts — passed through to wp-config.php by the official image
      WORDPRESS_AUTH_KEY: ${WORDPRESS_AUTH_KEY}
      WORDPRESS_SECURE_AUTH_KEY: ${WORDPRESS_SECURE_AUTH_KEY}
      WORDPRESS_LOGGED_IN_KEY: ${WORDPRESS_LOGGED_IN_KEY}
      WORDPRESS_NONCE_KEY: ${WORDPRESS_NONCE_KEY}
      WORDPRESS_AUTH_SALT: ${WORDPRESS_AUTH_SALT}
      WORDPRESS_SECURE_AUTH_SALT: ${WORDPRESS_SECURE_AUTH_SALT}
      WORDPRESS_LOGGED_IN_SALT: ${WORDPRESS_LOGGED_IN_SALT}
      WORDPRESS_NONCE_SALT: ${WORDPRESS_NONCE_SALT}
      # Load extra constants from mounted file
      WORDPRESS_CONFIG_EXTRA: |
        if ( file_exists( ABSPATH . 'wp-extra.php' ) ) {
            require_once ABSPATH . 'wp-extra.php';
        }
    volumes:
      - ./wp-content:/var/www/html/wp-content
      - ./config/wp-extra.php:/var/www/html/wp-extra.php:ro
      - ./config/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini:ro
      - ./config/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
    networks:
      - internal
      - dokploy-network
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=dokploy-network"

  # ── MariaDB ──────────────────────────────────────────────────────
  db:
    image: mariadb:10.11
    container_name: cargomarket_db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
      - ./config/mariadb.cnf:/etc/mysql/conf.d/custom.cnf:ro
    networks:
      - internal
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  # ── Redis (object cache) ─────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: cargomarket_redis
    restart: unless-stopped
    command: >
      redis-server
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --save ""
    volumes:
      - redis_data:/data
    networks:
      - internal

  # ── WP-CLI (run-once tool, not started by default) ───────────────
  wpcli:
    image: wordpress:cli-php8.3
    container_name: cargomarket_wpcli
    volumes:
      - ./wp-content:/var/www/html/wp-content
      - ./config/wp-extra.php:/var/www/html/wp-extra.php:ro
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      NETWORK_DOMAIN: ${NETWORK_DOMAIN}
    networks:
      - internal
    depends_on:
      - db
      - wordpress
    profiles:
      - tools
    entrypoint: wp
    user: "33:33"

volumes:
  db_data:
  redis_data:

networks:
  internal:
    driver: bridge
  dokploy-network:
    external: true
```

- [ ] **Step 2: Validate the compose file syntax**

```bash
docker compose config --quiet && echo "VALID"
```

Expected: `VALID` (no errors)

---

## Task 6: Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create `Makefile`**

```makefile
.PHONY: wp add-site backup-db restore-db

# ── Read NETWORK_DOMAIN from .env ────────────────────────────────
NETWORK_DOMAIN := $(shell grep -E '^NETWORK_DOMAIN=' .env | cut -d= -f2)
MYSQL_DATABASE  := $(shell grep -E '^MYSQL_DATABASE=' .env | cut -d= -f2)
MYSQL_USER      := $(shell grep -E '^MYSQL_USER=' .env | cut -d= -f2)
MYSQL_PASSWORD  := $(shell grep -E '^MYSQL_PASSWORD=' .env | cut -d= -f2)

## wp cmd="..."  —  Run any WP-CLI command inside the stack
## Example: make wp cmd="plugin list"
wp:
	docker compose --profile tools run --rm wpcli $(cmd)

## add-site slug=<slug> title="<title>" email=<email> domain=<domain>
## Example: make add-site slug=store1 title="Store 1" email=admin@store1.com domain=store1.com
add-site:
	@[ -n "$(slug)" ] && [ -n "$(title)" ] && [ -n "$(email)" ] && [ -n "$(domain)" ] || \
		(echo "Usage: make add-site slug=<slug> title=\"<title>\" email=<email> domain=<domain>" && exit 1)
	$(eval BLOG_ID := $(shell docker compose --profile tools run --rm -T wpcli \
		site create --slug=$(slug) --title="$(title)" --email=$(email) --porcelain 2>/dev/null | tr -d '\r\n'))
	@echo "Created site blog_id=$(BLOG_ID)"
	docker compose --profile tools run --rm wpcli db query \
		"UPDATE wp_blogs SET domain='$(domain)', path='/' WHERE blog_id=$(BLOG_ID);"
	docker compose --profile tools run --rm wpcli option update siteurl \
		"https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"
	docker compose --profile tools run --rm wpcli option update home \
		"https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"
	docker compose --profile tools run --rm wpcli plugin activate woocommerce \
		--url="$(domain)"
	@echo ""
	@echo "✔ Site ready: https://$(domain)"
	@echo "  Next: add '$(domain)' in Dokploy domain settings to get SSL."

## backup-db  —  Dump full database to backups/backup-YYYYMMDD-HHMMSS.sql
backup-db:
	@mkdir -p backups
	docker compose exec db mysqldump \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		> backups/backup-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "Backup saved to backups/"

## restore-db file=backups/<filename>.sql  —  Restore from a dump
restore-db:
	@[ -n "$(file)" ] || (echo "Usage: make restore-db file=backups/backup-YYYYMMDD-HHMMSS.sql" && exit 1)
	docker compose exec -T db mysql \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		< $(file)
	@echo "Database restored from $(file)"
```

- [ ] **Step 2: Verify Makefile parses**

```bash
make --dry-run wp cmd="--info" 2>&1 | head -5
```

Expected: shows the `docker compose` command without executing it.

---

## Task 7: Git Initialization + First Commit

**Files:** All files created so far.

- [ ] **Step 1: Create `.env` from `.env.example` and fill in real values**

```bash
cp .env.example .env
```

Then open `.env` and replace all placeholder values:
- Set `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` to strong random strings (min 24 chars, alphanumeric)
- Set `NETWORK_DOMAIN` to the actual primary domain pointing to your Dokploy VPS
- Generate WordPress salts by visiting `https://api.wordpress.org/secret-key/1.1/salt/` and pasting the output values

- [ ] **Step 2: Initialize git repository**

```bash
git init
git add .gitignore .env.example docker-compose.yml Makefile \
        config/ wp-content/sunrise.php \
        wp-content/mu-plugins/.gitkeep \
        wp-content/plugins/.gitkeep \
        wp-content/themes/.gitkeep \
        backups/.gitkeep \
        docs/
```

- [ ] **Step 3: Verify nothing sensitive is staged**

```bash
git status
```

Confirm `.env` does NOT appear in the staged files list. If it does, run `git reset HEAD .env`.

- [ ] **Step 4: Create initial commit**

```bash
git commit -m "feat: initial CargoMarket Multisite Docker stack"
```

- [ ] **Step 5: Add remote and push**

```bash
git remote add origin <your-git-repo-url>
git push -u origin main
```

Expected: push succeeds, repo visible in GitHub/Gitea.

---

## Task 8: Deploy Stack on Dokploy

> Performed in the **Dokploy web UI** on your VPS.

- [ ] **Step 1: Create a new Compose app in Dokploy**

1. Log in to Dokploy UI → **Projects** → your project → **+ New Service** → **Compose**
2. Name it `cargomarket-multisite`
3. Under **Source**, choose **Git** → connect repo → select branch `main`
4. Set **Docker Compose file path**: `docker-compose.yml`
5. Save

- [ ] **Step 2: Set environment variables in Dokploy**

In the service's **Environment** tab, paste all variables from `.env` (all key=value pairs). Dokploy stores these securely.

- [ ] **Step 3: Add the primary network domain**

In **Domains** tab → **+ Add Domain**:
- Domain: value of `NETWORK_DOMAIN` (e.g., `network.cargomarket.com`)
- Port: `80`
- Enable HTTPS: ✓
- Save → Traefik will provision Let's Encrypt cert automatically

- [ ] **Step 4: Deploy**

Click **Deploy** → watch logs until all three containers show `healthy` / `running`.

- [ ] **Step 5: Validate containers are running**

```bash
# SSH into VPS or use Dokploy terminal:
docker ps --filter "name=cargomarket" --format "table {{.Names}}\t{{.Status}}"
```

Expected:
```
NAMES                    STATUS
cargomarket_wordpress    Up X minutes (healthy)
cargomarket_db           Up X minutes (healthy)
cargomarket_redis        Up X minutes
```

- [ ] **Step 6: Validate WordPress is reachable**

Open `https://<NETWORK_DOMAIN>/wp-admin/install.php` in a browser.
Expected: WordPress installation page loads over HTTPS with a valid certificate.

---

## Task 9: Phase 1 — Install WordPress + Create Multisite Network

> Run these commands from the project directory (local machine or VPS SSH).
> Replace `network.cargomarket.com` with your actual `NETWORK_DOMAIN` value from `.env`.

- [ ] **Step 1: Run WordPress core install**

```bash
make wp cmd="core install \
  --url=https://network.cargomarket.com \
  --title='CargoMarket Network Admin' \
  --admin_user=admin \
  --admin_password='REPLACE_WITH_SECURE_PASSWORD' \
  --admin_email='admin@cargomarket.com' \
  --skip-email"
```

Expected output:
```
Success: WordPress installed successfully.
```

- [ ] **Step 2: Create the multisite network**

> Note: `wp core multisite-install` creates the network DB tables and prints
> wp-config.php instructions to stdout. Any wp-config.php changes it makes are
> intentionally overridden in Task 10 when we update `config/wp-extra.php`.

```bash
make wp cmd="core multisite-install \
  --url=https://network.cargomarket.com \
  --title='CargoMarket Network' \
  --admin_user=admin \
  --admin_email='admin@cargomarket.com'"
```

Expected output:
```
Success: Network installed. Don't forget to set up rewrite rules ...
```

The "don't forget" message is about `.htaccess` — handled next.

- [ ] **Step 3: Update `.htaccess` for Multisite**

```bash
make wp cmd="rewrite flush"
```

Expected: `Success: Rewrite rules flushed.`

- [ ] **Step 4: Verify network tables exist**

```bash
make wp cmd="db query 'SHOW TABLES LIKE \"wp_blogs\";'"
```

Expected: `wp_blogs` returned.

---

## Task 10: Phase 2 — Enable Full Multisite Config + Restart

- [ ] **Step 1: Edit `config/wp-extra.php` to Phase 2 (full multisite)**

Replace the entire contents of `config/wp-extra.php` with:

```php
<?php
/**
 * wp-extra.php — Phase 2 (multisite active)
 * Mounted into the container at /var/www/html/wp-extra.php
 */

// ── Multisite ─────────────────────────────────────────────────────
define( 'WP_ALLOW_MULTISITE', true );
define( 'MULTISITE', true );
define( 'SUBDOMAIN_INSTALL', false );
define( 'DOMAIN_CURRENT_SITE', getenv( 'NETWORK_DOMAIN' ) ?: 'localhost' );
define( 'PATH_CURRENT_SITE', '/' );
define( 'SITE_ID_CURRENT_SITE', 1 );
define( 'BLOG_ID_CURRENT_SITE', 1 );

// ── Domain mapping (sunrise.php dropin) ───────────────────────────
define( 'SUNRISE', 'on' );

// ── Redis object cache ────────────────────────────────────────────
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_CACHE', true );

// ── Performance ───────────────────────────────────────────────────
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// ── Security ──────────────────────────────────────────────────────
define( 'DISALLOW_FILE_EDIT', true );
```

- [ ] **Step 2: Commit Phase 2 config**

```bash
git add config/wp-extra.php
git commit -m "feat: enable WordPress Multisite constants (Phase 2)"
git push
```

- [ ] **Step 3: Redeploy in Dokploy to pick up the updated config**

In Dokploy UI → service → **Deploy** (or trigger via webhook).

The `wp-extra.php` file is mounted read-only from the repo. The WordPress container reads it on every request, so no restart is strictly needed — but redeploying ensures a clean state.

- [ ] **Step 4: Validate Network Admin loads**

Open `https://<NETWORK_DOMAIN>/wp-admin/network/` in a browser.

Expected: WordPress Network Admin dashboard loads without errors.

- [ ] **Step 5: Verify sunrise.php is loaded**

```bash
make wp cmd="eval 'echo defined(\"SUNRISE\") ? \"SUNRISE OK\" : \"SUNRISE MISSING\";'"
```

Expected output: `SUNRISE OK`

---

## Task 11: Install Plugins Network-Wide

- [ ] **Step 1: Install WooCommerce and Redis Cache**

```bash
make wp cmd="plugin install woocommerce redis-cache --activate-network"
```

Expected:
```
Installing WooCommerce ...
Plugin installed successfully.
Installing Redis Object Cache ...
Plugin installed successfully.
Network activating 'woocommerce'...
Network activating 'redis-cache'...
```

- [ ] **Step 2: Enable Redis object cache**

```bash
make wp cmd="redis enable"
```

Expected: `Success: Object cache enabled.`

- [ ] **Step 3: Verify Redis is connected**

```bash
make wp cmd="redis status"
```

Expected output includes: `Status: Connected`

- [ ] **Step 4: Verify WooCommerce is network-active**

```bash
make wp cmd="plugin list --status=active-network --fields=name"
```

Expected: `woocommerce` and `redis-cache` appear in the list.

- [ ] **Step 5: Commit (no file changes — this step is operational)**

No commit needed; plugin state is in the database.

---

## Task 12: Add First Store + Verify Domain Mapping

- [ ] **Step 1: Ensure the store's custom domain DNS points to the Dokploy VPS**

In your DNS provider, add an A record:
```
store1.com  →  A  →  <Dokploy VPS IP>
```

Wait for DNS propagation (typically 5–60 min). Verify:
```bash
nslookup store1.com
```

Expected: resolves to the VPS IP.

- [ ] **Step 2: Add the first store via Makefile**

```bash
make add-site slug=store1 title="Store 1" email="admin@store1.com" domain="store1.com"
```

Expected output:
```
Created site blog_id=2
✔ Site ready: https://store1.com
  Next: add 'store1.com' in Dokploy domain settings to get SSL.
```

- [ ] **Step 3: Add `store1.com` domain in Dokploy**

In Dokploy UI → `cargomarket-multisite` service → **Domains** → **+ Add Domain**:
- Domain: `store1.com`
- Port: `80`
- Enable HTTPS: ✓
- Save

Traefik provisions the Let's Encrypt cert automatically (may take ~60 seconds).

- [ ] **Step 4: Verify the store loads over HTTPS**

Open `https://store1.com` in a browser.

Expected: WordPress site loads with a valid SSL certificate. If redirected to network admin, wait 1–2 minutes for Let's Encrypt cert to provision and try again.

- [ ] **Step 5: Verify WooCommerce is active on the store**

```bash
make wp cmd="plugin status woocommerce --url=store1.com"
```

Expected: `Status: Network Active`

- [ ] **Step 6: Verify domain mapping in database**

```bash
make wp cmd="db query 'SELECT blog_id, domain, path FROM wp_blogs;'"
```

Expected:
```
blog_id  domain                       path
1        network.cargomarket.com      /
2        store1.com                   /
```

---

## Task 13: Operational Runbook

**Files:**
- Create: `docs/add-new-site.md`

- [ ] **Step 1: Create `docs/add-new-site.md`**

```markdown
# Adding a New Store to CargoMarket Multisite

## Prerequisites

1. The store's custom domain must have an **A record** pointing to the Dokploy VPS IP.
2. You must have SSH or terminal access to run `make` commands from the project root.

## Steps

### 1. Create the site

```bash
make add-site \
  slug=storeN \
  title="Store Name" \
  email="admin@storeN.com" \
  domain="storeN.com"
```

This command:
- Creates the WordPress subsite
- Updates `wp_blogs.domain` to the custom domain
- Updates `siteurl` and `home` options
- Activates WooCommerce on the new site

### 2. Add the domain in Dokploy

1. Open Dokploy UI → `cargomarket-multisite` → **Domains** → **+ Add Domain**
2. Domain: `storeN.com`, Port: `80`, HTTPS: ✓
3. Save — Traefik provisions the SSL certificate (~60s)

### 3. Verify

Open `https://storeN.com` — should load the new WordPress store with SSL.

## Troubleshooting

**SSL not working after adding domain:**
- Wait 2–3 minutes for Let's Encrypt ACME challenge to complete
- Ensure the domain's A record resolves correctly: `nslookup storeN.com`
- Check Traefik logs in Dokploy for certificate errors

**Site shows Network Admin instead of store:**
- The domain mapping in `wp_blogs` may not have applied. Run:
  ```bash
  make wp cmd="db query 'SELECT blog_id, domain FROM wp_blogs;'"
  ```
  Confirm `storeN.com` appears with the correct `blog_id`.

**WooCommerce not active:**
```bash
make wp cmd="plugin activate woocommerce --url=storeN.com"
```

## Backup Before Changes

```bash
make backup-db
```

Dumps to `backups/backup-YYYYMMDD-HHMMSS.sql`.
```

- [ ] **Step 2: Commit runbook**

```bash
git add docs/add-new-site.md
git commit -m "docs: add new-site provisioning runbook"
git push
```

---

## Self-Review Checklist

- [x] Task 1–2: Scaffold, PHP config → covers spec §5 File Structure
- [x] Task 3: MariaDB config → covers spec §3 `db` service
- [x] Task 4: wp-extra.php + sunrise.php → covers spec §4 Domain Mapping
- [x] Task 5: docker-compose.yml → covers spec §3 all services
- [x] Task 6: Makefile → covers spec §7
- [x] Task 7: Git init → covers spec §6 step 1
- [x] Task 8: Dokploy deploy → covers spec §6 steps 2–4
- [x] Task 9: WP core install + multisite → covers spec §4 Setup Sequence
- [x] Task 10: Phase 2 config → covers spec §4 wp-config constants
- [x] Task 11: Plugins → covers spec §6 step 5
- [x] Task 12: First store → covers spec §4 Adding a New Store
- [x] Task 13: Runbook → covers spec §5 docs/add-new-site.md
