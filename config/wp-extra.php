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
