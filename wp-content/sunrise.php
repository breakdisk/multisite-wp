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
