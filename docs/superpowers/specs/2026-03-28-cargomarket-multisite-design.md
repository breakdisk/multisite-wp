# CargoMarket Multisite — Design Spec
**Date:** 2026-03-28
**Project:** F:/CargoMarket-Multisite
**Status:** Approved

---

## 1. Summary

A Docker-containerized WordPress Multisite network hosting 6–20 independent WooCommerce stores, deployed as a single Docker Compose stack on an existing Dokploy VPS. Each store has its own custom domain with automatic SSL via Traefik + Let's Encrypt.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Dokploy VPS                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │         Docker Compose Stack                │   │
│  │                                             │   │
│  │  ┌──────────────┐   ┌──────────────────┐   │   │
│  │  │  WordPress   │   │    MariaDB        │   │   │
│  │  │  Multisite   │──▶│  (shared DB)      │   │   │
│  │  │  + WooComm.  │   │  wp_* tables      │   │   │
│  │  └──────┬───────┘   └──────────────────┘   │   │
│  │         │                                   │   │
│  │  ┌──────▼───────┐                           │   │
│  │  │    Redis     │  (object cache)            │   │
│  │  └──────────────┘                           │   │
│  │                                             │   │
│  │  Volumes: wp-content/, db-data/, uploads/   │   │
│  └─────────────────────────────────────────────┘   │
│                        │                            │
│  ┌─────────────────────▼────────────────────────┐  │
│  │   Traefik (built into Dokploy)               │  │
│  │   - Routes per domain → WordPress container  │  │
│  │   - Let's Encrypt SSL per custom domain      │  │
│  └─────────────────────┬────────────────────────┘  │
└────────────────────────┼───────────────────────────┘
                         │
        store1.com / store2.com / store3.com ...
```

**Key decisions:**
- Single Docker Compose stack (all-in-one) deployed as a Dokploy Compose app
- WordPress Multisite in subdirectory mode internally; per-site custom domains via `sunrise.php` domain mapping
- Shared MariaDB 10.11 (LTS) — one database, WordPress Multisite table prefixes per site
- Redis 7 for WooCommerce object caching (`allkeys-lru`, 256MB cap)
- Traefik (Dokploy built-in) handles routing + Let's Encrypt SSL per custom domain
- Named Docker volumes for persistence across restarts and redeployments

---

## 3. Docker Compose Services

### `wordpress`
- **Image:** `wordpress:6.7-php8.3-apache`
- **Environment:** `WORDPRESS_DB_*` credentials + `WORDPRESS_CONFIG_EXTRA` for multisite/Redis constants
- **Volumes:**
  - `./wp-content:/var/www/html/wp-content` (plugins, themes, mu-plugins, uploads)
  - `./config/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini`
  - `./config/php.ini:/usr/local/etc/php/conf.d/custom.ini`
- **Traefik labels:** one entrypoint per custom domain; wildcard catch-all for the network admin domain
- **Depends on:** `db`, `redis`

### `db`
- **Image:** `mariadb:10.11`
- **Environment:** `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`
- **Volume:** `db_data:/var/lib/mysql`
- **Config mount:** `./config/mariadb.cnf:/etc/mysql/conf.d/custom.cnf`
- **Tuning:** `innodb_buffer_pool_size=512M`, `max_connections=200`

### `redis`
- **Image:** `redis:7-alpine`
- **No exposed ports** (internal network only)
- **Volume:** `redis_data:/data`
- **Command:** `redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru`

---

## 4. WordPress Multisite & Domain Mapping

### Setup Sequence
1. WordPress installs on primary network domain: `network.cargomarket.com`
2. Multisite activated via WP-CLI: `wp core multisite-install`
3. Network mode: **subdirectory** (internal) + domain mapping overrides public domains
4. **Mercator** installed as a mu-plugin (`wp-content/mu-plugins/mercator/`) — provides custom domain mapping per site
5. Mercator's `sunrise.php` copied to `wp-content/sunrise.php` (WordPress dropin location) and enabled via `SUNRISE` constant

### `wp-config.php` Extra Constants (via `WORDPRESS_CONFIG_EXTRA`)
```php
define('WP_ALLOW_MULTISITE', true);
define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', false);
define('DOMAIN_CURRENT_SITE', 'network.cargomarket.com');
define('PATH_CURRENT_SITE', '/');
define('SITE_ID_CURRENT_SITE', 1);
define('BLOG_ID_CURRENT_SITE', 1);

// Domain mapping
define('SUNRISE', 'on');

// Redis
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_CACHE', true);

// WooCommerce performance
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');
```

### Adding a New Store (Per-Site Workflow)
1. `wp site create --slug=storeN --title="Store Name" --email=admin@storeN.com`
2. Map custom domain via Mercator: `wp mercator create <site_id> storeN.com`
3. Add domain in Dokploy → Traefik auto-provisions Let's Encrypt cert
4. Activate WooCommerce on the site: `wp plugin activate woocommerce --url=storeN.com`
5. Store is live at `storeN.com`

---

## 5. File Structure

```
CargoMarket-Multisite/
├── docker-compose.yml          # Main stack definition
├── .env                        # Secrets (DB pass, WP salts, domains) — gitignored
├── .env.example                # Template committed to git
├── .gitignore
├── Makefile                    # WP-CLI shortcuts
├── config/
│   ├── uploads.ini             # PHP upload limits (64M)
│   ├── php.ini                 # PHP tuning (memory, opcache)
│   └── mariadb.cnf             # DB tuning (InnoDB buffer, connections)
├── wp-content/
│   ├── sunrise.php             # Domain mapping dropin (copied from Mercator)
│   ├── mu-plugins/
│   │   └── mercator/           # Mercator domain mapping mu-plugin
│   ├── plugins/                # Shared plugins (WooCommerce, Redis Cache)
│   ├── themes/                 # Shared themes
│   └── uploads/                # User uploads (gitignored)
└── docs/
    └── add-new-site.md         # Runbook for spinning up a new store
```

---

## 6. Deployment Workflow on Dokploy

1. Push repo to Git (GitHub/Gitea)
2. Create a **Compose** app in Dokploy → point to repo + `docker-compose.yml`
3. Set environment variables in Dokploy's env panel (using `.env.example` as reference)
4. Deploy — Dokploy pulls images, starts stack, Traefik picks up labels
5. Run one-time WP-CLI setup via Dokploy terminal or SSH:
   - `wp core multisite-install`
   - `wp plugin install woocommerce redis-cache --activate-network`
   - `wp redis enable`
6. Add each store domain in Dokploy domain settings → SSL auto-provisioned

---

## 7. Makefile Shortcuts

```makefile
add-site:    # wp site create + domain map + WooCommerce activate
backup-db:   # mysqldump to /backups with timestamp
restore-db:  # restore from dump file
wp:          # pass-through: make wp cmd="plugin list --url=store1.com"
```

---

## 8. Out of Scope (for this phase)

- Per-site staging environments
- Automated DB backups (runbook provided, not automated)
- CDN integration (Cloudflare, BunnyCDN)
- SMTP/email service configuration
- CI/CD pipeline
