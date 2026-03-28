.PHONY: wp add-site backup-db restore-db

ifeq (,$(wildcard .env))
  $(error .env file not found — copy .env.example and fill in your values first)
endif

# ── Read variables from .env ─────────────────────────────────────
NETWORK_DOMAIN := $(shell grep -E '^NETWORK_DOMAIN=' .env | cut -d= -f2)
MYSQL_DATABASE  := $(shell grep -E '^MYSQL_DATABASE=' .env | cut -d= -f2)
MYSQL_USER      := $(shell grep -E '^MYSQL_USER=' .env | cut -d= -f2)
MYSQL_PASSWORD  := $(shell grep -E '^MYSQL_PASSWORD=' .env | cut -d= -f2)

# ── WP-CLI runner ────────────────────────────────────────────────
# Attaches to the running wordpress container's files + internal network.
# Works regardless of which compose project name Dokploy uses.
WPCLI = docker run --rm \
  --network cargomarket-internal \
  --volumes-from cargomarket_wordpress \
  -e WORDPRESS_DB_HOST=db:3306 \
  -e WORDPRESS_DB_NAME=$(MYSQL_DATABASE) \
  -e WORDPRESS_DB_USER=$(MYSQL_USER) \
  -e WORDPRESS_DB_PASSWORD=$(MYSQL_PASSWORD) \
  -e NETWORK_DOMAIN=$(NETWORK_DOMAIN) \
  --user 33:33 \
  --entrypoint wp \
  wordpress:cli-php8.3

## wp cmd="..."  —  Run any WP-CLI command
## Example: make wp cmd="plugin list"
wp:
	$(WPCLI) $(cmd)

## add-site slug=<slug> title="<title>" email=<email> domain=<domain>
## Example: make add-site slug=store1 title="Store 1" email=admin@store1.com domain=store1.com
add-site:
	@[ -n "$(slug)" ] && [ -n "$(title)" ] && [ -n "$(email)" ] && [ -n "$(domain)" ] || \
		{ echo "Usage: make add-site slug=<slug> title=\"<title>\" email=<email> domain=<domain>"; exit 1; }
	@set -e; \
	BLOG_ID=$$($(WPCLI) site create --slug=$(slug) --title="$(title)" --email=$(email) \
		--url="$(NETWORK_DOMAIN)" --porcelain 2>/dev/null | tr -d '\r\n'); \
	[ -n "$$BLOG_ID" ] || { echo "ERROR: wp site create returned no blog ID"; exit 1; }; \
	echo "Created site blog_id=$$BLOG_ID"; \
	$(WPCLI) db query "UPDATE wp_blogs SET domain='$(domain)', path='/' WHERE blog_id=$$BLOG_ID;"; \
	$(WPCLI) option update siteurl "https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"; \
	$(WPCLI) option update home "https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"; \
	$(WPCLI) plugin activate woocommerce --url="$(domain)"; \
	echo ""; \
	echo "✔ Site ready: https://$(domain)"; \
	echo "  Next: add '$(domain)' in Dokploy domain settings to get SSL."

## backup-db  —  Dump full database to backups/backup-YYYYMMDD-HHMMSS.sql
backup-db:
	@mkdir -p backups
	@set -e; \
	STAMP=$$(date +%Y%m%d-%H%M%S); \
	docker exec cargomarket_db mysqldump \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		> backups/backup-$$STAMP.sql; \
	echo "Backup saved to backups/backup-$$STAMP.sql"

## restore-db file=backups/<filename>.sql  —  Restore from a dump
restore-db:
	@[ -n "$(file)" ] || { echo "Usage: make restore-db file=backups/backup-YYYYMMDD-HHMMSS.sql"; exit 1; }
	docker exec -i cargomarket_db mysql \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		< $(file)
	@echo "Database restored from $(file)"
