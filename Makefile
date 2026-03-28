.PHONY: wp add-site backup-db restore-db

ifeq (,$(wildcard .env))
  $(error .env file not found — copy .env.example and fill in your values first)
endif

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
		{ echo "Usage: make add-site slug=<slug> title=\"<title>\" email=<email> domain=<domain>"; exit 1; }
	@set -e; \
	BLOG_ID=$$(docker compose --profile tools run --rm -T wpcli \
		site create --slug=$(slug) --title="$(title)" --email=$(email) \
		--url="$(NETWORK_DOMAIN)" --porcelain 2>/dev/null \
		| tr -d '\r\n'); \
	[ -n "$$BLOG_ID" ] || { echo "ERROR: wp site create returned no blog ID"; exit 1; }; \
	echo "Created site blog_id=$$BLOG_ID"; \
	docker compose --profile tools run --rm wpcli db query \
		"UPDATE wp_blogs SET domain='$(domain)', path='/' WHERE blog_id=$$BLOG_ID;"; \
	docker compose --profile tools run --rm wpcli option update siteurl \
		"https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"; \
	docker compose --profile tools run --rm wpcli option update home \
		"https://$(domain)" --url="$(NETWORK_DOMAIN)/$(slug)"; \
	docker compose --profile tools run --rm wpcli plugin activate woocommerce \
		--url="$(domain)"; \
	echo ""; \
	echo "✔ Site ready: https://$(domain)"; \
	echo "  Next: add '$(domain)' in Dokploy domain settings to get SSL."

## backup-db  —  Dump full database to backups/backup-YYYYMMDD-HHMMSS.sql
backup-db:
	@mkdir -p backups
	@set -e; \
	STAMP=$$(date +%Y%m%d-%H%M%S); \
	docker compose exec -T db mysqldump \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		> backups/backup-$$STAMP.sql; \
	echo "Backup saved to backups/backup-$$STAMP.sql"

## restore-db file=backups/<filename>.sql  —  Restore from a dump
restore-db:
	@[ -n "$(file)" ] || { echo "Usage: make restore-db file=backups/backup-YYYYMMDD-HHMMSS.sql"; exit 1; }
	docker compose exec -T db mysql \
		-u$(MYSQL_USER) \
		-p$(MYSQL_PASSWORD) \
		$(MYSQL_DATABASE) \
		< $(file)
	@echo "Database restored from $(file)"
