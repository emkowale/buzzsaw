<?php
/*
 * Plugin Name: Buzzsaw
 * Description: Copies each product’s Featured Image and original-art (custom field URL) into a fixed mount: /mnt/ccpi/mnt/nas/Website-Orders/<Site Title>/<Product Title>. Skips identical files (same size). Background-safe with live progress and nightly cron (1–5 AM). Auto-updates from GitHub.
 * Author: Eric Kowalewski
 * Version: 1..1
 * Update URI: https://github.com/emkowale/buzzsaw
 */

if (!defined('ABSPATH')) exit;

define('BUZZSAW_VERSION', '1..1');
define('BUZZSAW_PATH', plugin_dir_path(__FILE__));
define('BUZZSAW_URL',  plugin_dir_url(__FILE__));
define('BUZZSAW_BASE_PATH', '/mnt/ccpi/mnt/nas/Website-Orders');

require_once BUZZSAW_PATH . 'includes/class-buzzsaw-admin.php';
require_once BUZZSAW_PATH . 'includes/class-buzzsaw-pusher.php';
require_once BUZZSAW_PATH . 'includes/class-buzzsaw-cron.php';

add_action('plugins_loaded', function () {
    Buzzsaw_Admin::init();
    Buzzsaw_Pusher::init();
    Buzzsaw_Cron::init();
    Buzzsaw_Updater::init();
});

register_activation_hook(__FILE__, ['Buzzsaw_Cron', 'activate']);
register_deactivation_hook(__FILE__, ['Buzzsaw_Cron', 'deactivate']);

// === GitHub Updater (built-in) =================================================
if (!defined('BUZZSAW_GH_OWNER')) define('BUZZSAW_GH_OWNER', 'emkowale');
if (!defined('BUZZSAW_GH_REPO'))  define('BUZZSAW_GH_REPO',  'buzzsaw');
if (!defined('BUZZSAW_GH_TOKEN')) define('BUZZSAW_GH_TOKEN', '');

class Buzzsaw_Updater {
    public static function init() {
        add_filter('pre_set_site_transient_update_plugins', [__CLASS__,'check']);
        add_filter('plugins_api', [__CLASS__,'info'], 10, 3);
    }

    protected static function api($path) {
        $url = 'https://api.github.com' . $path;
        $args = [
            'headers' => array_filter([
                'Accept'       => 'application/vnd.github+json',
                'User-Agent'   => 'buzzsaw-updater',
                'Authorization'=> BUZZSAW_GH_TOKEN ? ('token ' . BUZZSAW_GH_TOKEN) : null,
            ]),
            'timeout' => 20,
        ];
        $res = wp_remote_get($url, $args);
        if (is_wp_error($res)) return $res;
        $code = wp_remote_retrieve_response_code($res);
        $body = json_decode(wp_remote_retrieve_body($res), true);
        if ($code >= 400) return new WP_Error('gh_api', 'GitHub API HTTP '.$code, $body);
        return $body;
    }

    protected static function latest_release() {
        $rel = self::api("/repos/".BUZZSAW_GH_OWNER."/".BUZZSAW_GH_REPO."/releases/latest");
        if (is_wp_error($rel)) return $rel;
        if (!is_array($rel) || empty($rel['tag_name'])) return new WP_Error('gh_api', 'Bad release payload');
        return $rel;
    }

    public static function pick_zip($rel) {
        $zip = '';
        if (!empty($rel['assets'])) {
            foreach ($rel['assets'] as $a) {
                if (!empty($a['browser_download_url']) && preg_match('/\.zip$/i', $a['browser_download_url'])) {
                    $zip = $a['browser_download_url']; break;
                }
            }
        }
        if (!$zip && !empty($rel['zipball_url'])) $zip = $rel['zipball_url'];
        return $zip;
    }

    public static function check($transient) {
        if (empty($transient) || !is_object($transient)) return $transient;
        $plugin_file = plugin_basename(__FILE__);
        $current = BUZZSAW_VERSION;

        $rel = self::latest_release();
        if (is_wp_error($rel)) return $transient;

        $tag = ltrim($rel['tag_name'], 'vV');
        if (version_compare($tag, $current, '<=')) return $transient;

        $obj = new stdClass();
        $obj->slug = 'buzzsaw';
        $obj->plugin = $plugin_file;
        $obj->new_version = $tag;
        $obj->url = "https://github.com/".BUZZSAW_GH_OWNER."/".BUZZSAW_GH_REPO."/releases/tag/v".$tag;
        $obj->package = self::pick_zip($rel);
        $obj->tested = '6.8';
        $obj->requires_php = '7.4';

        $transient->response[$plugin_file] = $obj;
        return $transient;
    }

    public static function info($result, $action, $args) {
        if ($action !== 'plugin_information' || empty($args->slug) || $args->slug !== 'buzzsaw') return $result;

        $rel = self::latest_release();
        if (is_wp_error($rel)) return $result;

        $tag = ltrim($rel['tag_name'], 'vV');
        $info = new stdClass();
        $info->name = 'Buzzsaw';
        $info->slug = 'buzzsaw';
        $info->version = $tag;
        $info->author = '<a href="https://github.com/'.BUZZSAW_GH_OWNER.'">'.esc_html(BUZZSAW_GH_OWNER).'</a>';
        $info->homepage = "https://github.com/".BUZZSAW_GH_OWNER."/".BUZZSAW_GH_REPO;
        $info->download_link = self::pick_zip($rel);
        $info->requires = '6.0';
        $info->tested = '6.8';
        $info->requires_php = '7.4';
        $info->last_updated = isset($rel['published_at']) ? $rel['published_at'] : '';

        $info->sections = [
            'description' => 'Copies Featured Image + original-art to a fixed mounted path. Background-safe, nightly cron, and size-based skip.',
            'changelog'   => !empty($rel['body']) ? wp_kses_post(nl2br($rel['body'])) : 'See GitHub releases.',
        ];

        return $info;
    }
}
// =============================================================================
