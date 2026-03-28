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
