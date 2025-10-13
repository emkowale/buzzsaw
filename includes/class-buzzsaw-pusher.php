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
