<?php
if (!defined('ABSPATH')) exit;

class Buzzsaw_Admin {
    public static function init() {
        add_action('admin_menu', [__CLASS__, 'menu']);
        add_action('admin_enqueue_scripts', [__CLASS__, 'assets']);
    }

    public static function menu() {
        add_menu_page(
            'Buzzsaw',
            'Buzzsaw',
            'manage_woocommerce',
            'buzzsaw',
            [__CLASS__, 'render_push'],
            'dashicons-controls-repeat',
            58
        );
        add_submenu_page('buzzsaw', 'Settings', 'Settings', 'manage_woocommerce', 'buzzsaw-settings', [__CLASS__, 'render_settings']);
        add_submenu_page('buzzsaw', 'Push to thebeartraxs.com', 'Push to thebeartraxs.com', 'manage_woocommerce', 'buzzsaw-push', [__CLASS__, 'render_push']);
        remove_submenu_page('buzzsaw','buzzsaw');
        // Remove the auto-added first child that duplicates the parent
        remove_submenu_page('buzzsaw', 'buzzsaw');
    }

    public static function assets($hook) {
        if (strpos($hook, 'buzzsaw') === false) return;
        wp_enqueue_style('buzzsaw-admin', BUZZSAW_URL.'assets/css/admin.css', [], BUZZSAW_VERSION);
        wp_enqueue_script('buzzsaw-push', BUZZSAW_URL.'assets/js/push.js', ['jquery','wp-api'], BUZZSAW_VERSION, true);
        wp_localize_script('buzzsaw-push', 'BUZZSAW', [
            'rest'   => esc_url_raw(rest_url('buzzsaw/v1')),
            'nonce'  => wp_create_nonce('wp_rest'),
            'site'   => get_bloginfo('name'),
        ]);
    }

    /** Read-only Settings screen showing the hardcoded base path */
    public static function render_settings() {
        $exists = is_dir(BUZZSAW_BASE_PATH) ? 'Yes' : 'No';
        $writable = is_writable(BUZZSAW_BASE_PATH) ? 'Yes' : 'No';
        echo '<div class="wrap">';
        echo '<h1>Buzzsaw — Settings</h1>';
        echo '<p><strong>Destination (fixed):</strong> <code>'.esc_html(BUZZSAW_BASE_PATH).'</code></p>';
        echo '<p><strong>Exists:</strong> '.$exists.' &nbsp; | &nbsp; <strong>Writable:</strong> '.$writable.'</p>';
        echo '<p class="description">Path is locked by the system administrator and cannot be changed in WordPress.</p>';
        echo '</div>';
    }

    public static function render_push() {
        ?>
        <div class="wrap">
            <h1>Push to thebeartraxs.com</h1>
            <p>This copies each product’s <strong>Product Image</strong> (featured image) and the <strong>original-art</strong> file (via its URL) into
            <code><?php echo esc_html(BUZZSAW_BASE_PATH); ?></code><code>/&lt;Site Title&gt;/&lt;Product Title&gt;</code>. Identical files (same size) are skipped.</p>

            <div id="buzzsaw-controls">
                <button id="buzzsaw-start" class="button button-primary">Start Push</button>
                <button id="buzzsaw-cancel" class="button" style="display:none;">Cancel</button>
            </div>

            <div id="buzzsaw-progress">
                <canvas id="buzzsaw-pie" width="160" height="160"></canvas>
                <div>
                    <div id="buzzsaw-pct">0%</div>
                    <div id="buzzsaw-status">Idle</div>
                </div>
            </div>

            <p class="description">Safe to leave this page — processing continues in the background.</p>
        </div>
        <?php
    }
}