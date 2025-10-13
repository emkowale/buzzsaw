# Buzzsaw (Affiliate-Side) — WordPress/WooCommerce Plugin

**Purpose:** Copy each product’s **Featured Image** and **original-art** (custom field URL) into a **fixed mount path** on the server under:

```
/mnt/ccpi/mnt/nas/Website-Orders/<Site Title>/<Product Title>/
```

Buzzsaw runs **manually** (from WP-Admin) and **nightly** (cron, random time 1–5 AM). It **skips** files that already exist with the same **size**. Background processing continues if the admin user leaves the page, and the UI shows a live progress pie.

> **Security:** The base path is **hardcoded** and **not configurable** by site admins (to prevent accidental or malicious changes).

---

## Features

- Fixed destination: `BUZZSAW_BASE_PATH = /mnt/ccpi/mnt/nas/Website-Orders`
- Directory structure: `Website-Orders/<Site Title>/<Product Title>/`
- Two files per product:
  1) **Featured Image** (product thumbnail file)
  2) **original-art** (URL in custom field)
     - If the URL points inside the local WP uploads, copy bytes directly
     - If it’s external, Buzzsaw **fetches** it via HTTP(S)
- **Skip** if destination file exists with the **same size**
- Background-safe, batched processing with live **progress pie**
- **Nightly cron** at a random time between **1–5 AM** local

## Auto-Updates (via GitHub)

Buzzsaw contains a built-in updater that checks the latest GitHub **Release** for this repository.
Configure these constants in `buzzsaw.php` to point to your repo (or leave defaults and name your repo `YOURORG/buzzsaw`):

```php
define('BUZZSAW_GH_OWNER', 'YOURORG');
define('BUZZSAW_GH_REPO',  'buzzsaw');
define('BUZZSAW_GH_TOKEN', ''); // optional: personal access token to avoid API rate limits
```

Tag your releases like `v1.1.4` and upload a ZIP asset (e.g., `buzzsaw-v1.1.4.zip`). WordPress will see the update and install it from WP Admin → Plugins.

## Install

1. Ensure mount is active and writable: `/mnt/ccpi/mnt/nas/Website-Orders`
2. Upload `buzzsaw/` to `/wp-content/plugins/` or install the ZIP.
3. Activate **Buzzsaw**.
4. Run a manual push in **Buzzsaw → Push to thebeartraxs.com**.

## Blueprint (Full Source)

> This section contains the full source for all plugin files. Copy these to reproduce the plugin from scratch.

### File Tree

```
buzzsaw/
├── buzzsaw.php
├── includes/
│   ├── class-buzzsaw-admin.php
│   ├── class-buzzsaw-pusher.php
│   └── class-buzzsaw-cron.php
├── assets/
│   ├── css/
│   │   └── admin.css
│   └── js/
│       └── push.js
├── README.md
└── CHANGELOG.md
```

### `buzzsaw.php`
```php
<?php
/*
 * Plugin Name: Buzzsaw
 * Description: Copies each product’s Featured Image and original-art into /mnt/ccpi/mnt/nas/Website-Orders/<Site Title>/<Product Title>. Skips identical files (same size). Background-safe with live progress and nightly cron (1–5 AM).
 * Author: Eric Kowalewski
 * Version: 1.1.4
 * Update URI: https://github.com/YOURORG/buzzsaw
 * Last Updated: 2025-10-13 18:20 EDT
 */

if (!defined('ABSPATH')) exit;

define('BUZZSAW_VERSION', '1.1.4');
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

// === GitHub Updater (built-in) ===============================================
// Configure your repo owner/org and optional token (to avoid API rate limit).
if (!defined('BUZZSAW_GH_OWNER')) define('BUZZSAW_GH_OWNER', 'YOURORG'); // TODO: set your GitHub org/user
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
        $owner = BUZZSAW_GH_OWNER;
        $repo  = BUZZSAW_GH_REPO;
        $rel = self::api("/repos/$owner/$repo/releases/latest");
        if (is_wp_error($rel)) return $rel;
        if (!is_array($rel) || empty($rel['tag_name'])) return new WP_Error('gh_api', 'Bad release payload');
        return $rel;
    }

    public static function check($transient) {
        if (empty($transient) || !is_object($transient)) return $transient;
        $plugin_file = plugin_basename(__FILE__);
        $current = BUZZSAW_VERSION;

        $rel = self::latest_release();
        if (is_wp_error($rel)) return $transient;

        $tag = ltrim($rel['tag_name'], 'vV');
        if (version_compare($tag, $current, '<=')) return $transient;

        $zip = '';
        if (!empty($rel['assets'])) {
            foreach ($rel['assets'] as $a) {
                if (!empty($a['browser_download_url']) && preg_match('/\.zip$/i', $a['browser_download_url'])) {
                    $zip = $a['browser_download_url'];
                    break;
                }
            }
        }
        if (!$zip && !empty($rel['zipball_url'])) {
            $zip = $rel['zipball_url'];
        }

        $obj = new stdClass();
        $obj->slug = 'buzzsaw';
        $obj->plugin = $plugin_file;
        $obj->new_version = $tag;
        $obj->url = "https://github.com/".BUZZSAW_GH_OWNER."/".BUZZSAW_GH_REPO."/releases/tag/v".$tag;
        $obj->package = $zip;
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
        $zip = '';
        if (!empty($rel['assets'])) {
            foreach ($rel['assets'] as $a) {
                if (!empty($a['browser_download_url']) && preg_match('/\.zip$/i', $a['browser_download_url'])) {
                    $zip = $a['browser_download_url']; break;
                }
            }
        }
        if (!$zip && !empty($rel['zipball_url'])) $zip = $rel['zipball_url'];

        $info = new stdClass();
        $info->name = 'Buzzsaw';
        $info->slug = 'buzzsaw';
        $info->version = $tag;
        $info->author = '<a href="https://github.com/'.BUZZSAW_GH_OWNER.'">'.esc_html(BUZZSAW_GH_OWNER).'</a>';
        $info->homepage = "https://github.com/".BUZZSAW_GH_OWNER."/".BUZZSAW_GH_REPO;
        $info->download_link = $zip;
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

```

### `includes/class-buzzsaw-admin.php`
```php
<?php
/*
 * File: includes/class-buzzsaw-admin.php
 * Description: Admin menu, read-only Settings, and push UI.
 * Plugin: Buzzsaw
 * Author: Eric Kowalewski
 * Last Updated: 2025-10-13 18:20 EDT
 */

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
        add_submenu_page('buzzsaw', 'Push to thebeartraxs.com', 'Push to thebeartraxs.com', 'manage_woocommerce', 'buzzsaw', [__CLASS__, 'render_push']);
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

```

### `includes/class-buzzsaw-pusher.php`
```php
<?php
/*
 * File: includes/class-buzzsaw-pusher.php
 * Description: REST routes to start/cancel push and poll progress; batch processor writing to hardcoded local mount.
 * Plugin: Buzzsaw
 * Author: Eric Kowalewski
 * Last Updated: 2025-10-13 18:20 EDT
 */

if (!defined('ABSPATH')) exit;

class Buzzsaw_Pusher {
    const STATE_KEY = 'buzzsaw_push_state'; // ['total'=>int,'done'=>int,'running'=>bool,'last'=>'msg','job_id'=>string]

    public static function init() {
        add_action('rest_api_init', [__CLASS__, 'routes']);
        add_action('buzzsaw_run_batch', [__CLASS__, 'run_batch']);
    }

    public static function routes() {
        register_rest_route('buzzsaw/v1', '/start', [
            'methods'  => 'POST',
            'callback' => [__CLASS__,'start'],
            'permission_callback' => function(){ return current_user_can('manage_woocommerce'); }
        ]);
        register_rest_route('buzzsaw/v1', '/progress', [
            'methods'  => 'GET',
            'callback' => [__CLASS__,'progress'],
            'permission_callback' => function(){ return current_user_can('manage_woocommerce'); }
        ]);
        register_rest_route('buzzsaw/v1', '/cancel', [
            'methods'  => 'POST',
            'callback' => [__CLASS__,'cancel'],
            'permission_callback' => function(){ return current_user_can('manage_woocommerce'); }
        ]);
    }

    public static function start(WP_REST_Request $req) {
        $work = self::build_worklist();
        $state = [
            'total'   => count($work),
            'done'    => 0,
            'running' => true,
            'last'    => 'Queued '.count($work).' items',
            'job_id'  => wp_generate_uuid4(),
            'started' => current_time('timestamp')
        ];
        set_transient(self::STATE_KEY, $state, HOUR_IN_SECONDS);
        set_transient(self::STATE_KEY.'_'.$state['job_id'], $work, 6 * HOUR_IN_SECONDS);

        do_action('buzzsaw_run_batch', $state['job_id']);
        if (!wp_next_scheduled('buzzsaw_run_batch', [$state['job_id']])) {
            wp_schedule_single_event(time()+5, 'buzzsaw_run_batch', [$state['job_id']]);
        }

        return ['ok'=>true, 'job_id'=>$state['job_id']];
    }

    public static function progress() {
        $state = get_transient(self::STATE_KEY);
        return $state ?: ['total'=>0,'done'=>0,'running'=>false,'last'=>'Idle'];
    }

    public static function cancel() {
        $state = get_transient(self::STATE_KEY);
        if ($state && !empty($state['job_id'])) {
            delete_transient(self::STATE_KEY.'_'.$state['job_id']);
        }
        delete_transient(self::STATE_KEY);
        return ['ok'=>true];
    }

    protected static function build_worklist() {
        $company = get_bloginfo('name');
        $work = [];

        $ids = get_posts([
            'post_type'      => 'product',
            'post_status'    => 'publish',
            'fields'         => 'ids',
            'posts_per_page' => -1,
            'no_found_rows'  => true,
        ]);

        foreach ($ids as $pid) {
            $product_title = get_the_title($pid) ?: ('product-' . $pid);

            if ($thumb_id = get_post_thumbnail_id($pid)) {
                $file = get_attached_file($thumb_id);
                if (is_readable($file)) {
                    $work[] = self::make_item($company, $product_title, $file);
                }
            }

            $orig = trim((string) get_post_meta($pid, 'original-art', true));
            if (!empty($orig)) {
                $local = self::maybe_local_path_from_url($orig);
                if ($local && is_readable($local)) {
                    $work[] = self::make_item($company, $product_title, $local);
                } else {
                    $work[] = self::make_item($company, $product_title, $orig);
                }
            }
        }

        $seen = [];
        $final = [];
        foreach ($work as $w) {
            $k = $w['dir'].'|'.$w['name'];
            if (!isset($seen[$k])) { $seen[$k] = true; $final[] = $w; }
        }
        return $final;
    }

    protected static function sanitize_segment($s) {
        $s = wp_strip_all_tags($s);
        $s = preg_replace('~[\/\\:\*\?"<>\|\x00-\x1F]+~u', '-', $s);
        $s = preg_replace('~\s+~u', ' ', $s);
        $s = trim($s, " .\t\n\r\0\x0B");
        return $s !== '' ? $s : 'untitled';
    }

    protected static function make_item($company, $product_title, $source) {
        $company = self::sanitize_segment($company);
        $product_title = self::sanitize_segment($product_title);
        $dir = $company.'/'.$product_title; // relative to hard base path

        if (is_string($source) && file_exists($source)) {
            return [
                'dir'   => $dir,
                'name'  => basename($source),
                'size'  => filesize($source),
                'path'  => $source,
                'is_url'=> false,
            ];
        }
        $name = basename(parse_url($source, PHP_URL_PATH) ?: 'remote-file');
        if ($name === '' || $name === false) $name = 'remote-file';
        return [
            'dir'   => $dir,
            'name'  => $name,
            'size'  => 0,
            'path'  => $source,
            'is_url'=> true,
        ];
    }

    protected static function maybe_local_path_from_url($url) {
        $upload = wp_get_upload_dir();
        if (!empty($upload['baseurl']) && strpos($url, $upload['baseurl']) === 0) {
            $rel = substr($url, strlen($upload['baseurl']));
            return $upload['basedir'] . $rel;
        }
        return null;
    }

    public static function run_batch($job_id) {
        $state = get_transient(self::STATE_KEY);
        if (!$state || empty($state['running']) || $state['job_id'] !== $job_id) return;

        $work = get_transient(self::STATE_KEY.'_'.$job_id);
        if (!$work || empty($work)) {
            $state['running']=false; $state['last']='Done'; set_transient(self::STATE_KEY, $state, HOUR_IN_SECONDS);
            return;
        }

        $chunk = array_splice($work, 0, 6);
        foreach ($chunk as $item) {
            $msg = self::ensure_local_file($item);
            $state['done']++;
            $state['last'] = $msg;
            set_transient(self::STATE_KEY, $state, HOUR_IN_SECONDS);
        }

        set_transient(self::STATE_KEY.'_'.$job_id, $work, 6 * HOUR_IN_SECONDS);

        if (!empty($work)) {
            wp_schedule_single_event(time()+5, 'buzzsaw_run_batch', [$job_id]);
        } else {
            $state['running']=false; $state['last']='Done'; set_transient(self::STATE_KEY, $state, HOUR_IN_SECONDS);
        }
    }

    protected static function ensure_local_file($item) {
        $base = rtrim(BUZZSAW_BASE_PATH, '/'); // hardcoded
        $dest_dir = $base . '/' . $item['dir'];
        if (!wp_mkdir_p($dest_dir)) {
            return 'mkdir failed: ' . $dest_dir;
        }
        $dest = $dest_dir . '/' . $item['name'];

        // If destination exists and size matches, skip
        if (file_exists($dest) && $item['size'] > 0 && filesize($dest) === (int)$item['size']) {
            return 'Skip (same): ' . $dest;
        }

        if ($item['is_url']) {
            $head = wp_remote_head($item['path'], ['timeout'=>15]);
            $remote_size = 0;
            if (!is_wp_error($head)) {
                $len = wp_remote_retrieve_header($head, 'content-length');
                if ($len) $remote_size = (int)$len;
            }
            if (file_exists($dest) && $remote_size > 0 && filesize($dest) === $remote_size) {
                return 'Skip (same): ' . $dest;
            }

            $resp = wp_remote_get($item['path'], ['timeout'=>45]);
            if (is_wp_error($resp)) return 'Fetch failed: '.$resp->get_error_message();
            $body = wp_remote_retrieve_body($resp);
            if ($body === '' && wp_remote_retrieve_response_code($resp) >= 400) return 'Fetch HTTP '.wp_remote_retrieve_response_code($resp);
            $ok = file_put_contents($dest, $body);
            if ($ok === false) return 'Write failed: ' . $dest;
            return 'Fetched: ' . $dest;
        }

        if (!is_readable($item['path'])) {
            return 'Read failed: '.$item['path'];
        }
        if (!@copy($item['path'], $dest)) {
            $in = @fopen($item['path'], 'rb');
            $out = @fopen($dest, 'wb');
            if (!$in || !$out) return 'Copy failed: '.$item['path'].' -> '.$dest;
            stream_copy_to_stream($in, $out);
            @fclose($in); @fclose($out);
        }
        return 'Copied: ' . $dest;
    }
}

```

### `includes/class-buzzsaw-cron.php`
```php
<?php
/*
 * File: includes/class-buzzsaw-cron.php
 * Description: Nightly single-event scheduling with random 1–5 AM window.
 * Plugin: Buzzsaw
 * Author: Eric Kowalewski
 * Last Updated: 2025-10-13 18:20 EDT
 */

if (!defined('ABSPATH')) exit;

class Buzzsaw_Cron {
    const HOOK = 'buzzsaw_nightly_push';

    public static function init() {
        add_action(self::HOOK, [__CLASS__, 'run_and_reschedule']);
    }

    public static function activate() {
        self::schedule_next();
    }

    public static function deactivate() {
        $crons = _get_cron_array();
        if (is_array($crons)) {
            foreach ($crons as $ts => $events) {
                foreach ($events as $hook => $details) {
                    if ($hook === self::HOOK) {
                        wp_unschedule_event($ts, self::HOOK);
                    }
                }
            }
        }
    }

    public static function run_and_reschedule() {
        $req = new WP_REST_Request('POST', '/buzzsaw/v1/start');
        $res = rest_do_request($req);
        self::schedule_next(true);
    }

    protected static function schedule_next($tomorrow = false) {
        $tz_string = get_option('timezone_string') ?: 'America/Detroit';
        try { $tz = new DateTimeZone($tz_string); } catch (Exception $e) { $tz = new DateTimeZone('America/Detroit'); }
        $now = new DateTime('now', $tz);

        $day = $tomorrow ? (clone $now)->modify('+1 day') : (clone $now);
        $hour = rand(1, 5);
        $minute = rand(0, 59);
        $when = new DateTime($day->format('Y-m-d').' '.$hour.':'.$minute.':00', $tz);

        if ($when <= $now) $when->modify('+1 day');

        wp_schedule_single_event($when->getTimestamp(), self::HOOK);
    }
}

```

### `assets/js/push.js`
```javascript
/*
 * File: assets/js/push.js
 * Description: Start/cancel push, poll progress, draw a percentage pie; processing continues server-side.
 * Plugin: Buzzsaw
 * Author: Eric Kowalewski
 * Last Updated: 2025-10-13 18:20 EDT
 */
(function($){
  let polling = null;

  function drawPie(pct){
    const c = document.getElementById('buzzsaw-pie');
    if(!c) return;
    const ctx = c.getContext('2d');
    const r = c.width/2, cx = r, cy = r;
    ctx.clearRect(0,0,c.width,c.height);

    ctx.beginPath(); ctx.arc(cx,cy,r-4,0,2*Math.PI); ctx.lineWidth = 8; ctx.strokeStyle = '#e1e5ea'; ctx.stroke();
    const end = (pct/100)*2*Math.PI;
    ctx.beginPath(); ctx.arc(cx,cy,r-4,-Math.PI/2, end - Math.PI/2); ctx.lineWidth = 8; ctx.strokeStyle = '#2271b1'; ctx.stroke();

    $('#buzzsaw-pct').text(Math.floor(pct)+'%');
  }

  function poll(){
    $.ajax({
      url: BUZZSAW.rest + '/progress',
      method: 'GET',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(st => {
      const total = st.total||0, done = st.done||0;
      const pct = total ? (done/total*100) : 0;
      drawPie(pct);
      $('#buzzsaw-status').text(st.last || 'Working…');
      if (!st.running) stopPolling();
    });
  }

  function startPolling(){ if (!polling) polling = setInterval(poll, 1500); }
  function stopPolling(){ if (polling) { clearInterval(polling); polling = null; poll(); } }

  $(document).on('click', '#buzzsaw-start', function(){
    $('#buzzsaw-status').text('Queuing…');
    $.ajax({
      url: BUZZSAW.rest + '/start',
      method: 'POST',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(() => {
      $('#buzzsaw-cancel').show();
      startPolling();
      poll();
    }).fail(xhr => {
      alert('Start failed: ' + (xhr.responseJSON && xhr.responseJSON.message ? xhr.responseJSON.message : 'Unknown error'));
    });
  });

  $(document).on('click', '#buzzsaw-cancel', function(){
    $.ajax({
      url: BUZZSAW.rest + '/cancel',
      method: 'POST',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(() => {
      stopPolling();
      $('#buzzsaw-status').text('Canceled');
      $('#buzzsaw-cancel').hide();
    });
  });

  $(function(){ drawPie(0); poll(); });
})(jQuery);

```

### `assets/css/admin.css`
```css
/*
 * File: assets/css/admin.css
 * Description: Admin styling for Buzzsaw push pie and layout.
 * Plugin: Buzzsaw
 * Author: Eric Kowalewski
 * Last Updated: 2025-10-13 18:20 EDT
 */
#buzzsaw-progress{ display:flex; align-items:center; gap:16px; margin-top:16px; }
#buzzsaw-pct{ font-size: 28px; font-weight: 600; }
#buzzsaw-status{ color:#444; opacity:.9; }
#buzzsaw-controls .button{ margin-right:8px; }

```

---

## GitHub: Repo, Changelog, Releases

### Initialize repo & first push
```bash
cd /path/to/buzzsaw
git init
printf ".DS_Store\nnode_modules\nvendor\n*.zip\n.idea\n.vscode\n" > .gitignore
git add .
git commit -m "feat: Buzzsaw v1.1.4 (hardcoded path) + updater + README blueprint + CHANGELOG"
git branch -M main
git remote add origin git@github.com:YOURORG/buzzsaw.git
git push -u origin main
```

### Tag a release
```bash
git tag -a v1.1.4 -m "Buzzsaw v1.1.4 — updater + hardcoded path"
git push origin v1.1.4
```

### Create GitHub Release (UI)
- Create a new Release from **v1.1.4**
- Upload the packaged zip
- Paste the changelog entry

## License
GPLv2 or later
