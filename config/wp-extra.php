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
