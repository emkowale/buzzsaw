<?php
if (!defined('ABSPATH')) exit;

class Buzzsaw_Pusher {
    const STATE_KEY = 'buzzsaw_push_state';

    public static function init(){
        add_action('rest_api_init', [__CLASS__,'routes']);
        add_action('buzzsaw_run_batch', [__CLASS__,'run_batch']);
    }

    public static function routes(){
        register_rest_route('buzzsaw/v1','/start',[
            'methods'=>'POST','callback'=>[__CLASS__,'start'],
            'permission_callback'=>fn()=>current_user_can('manage_woocommerce')
        ]);
        register_rest_route('buzzsaw/v1','/progress',[
            'methods'=>'GET','callback'=>[__CLASS__,'progress'],
            'permission_callback'=>fn()=>current_user_can('manage_woocommerce')
        ]);
        register_rest_route('buzzsaw/v1','/cancel',[
            'methods'=>'POST','callback'=>[__CLASS__,'cancel'],
            'permission_callback'=>fn()=>current_user_can('manage_woocommerce')
        ]);
    }

    public static function start(WP_REST_Request $r){
        $work = self::build_worklist();
        $state = ['total'=>count($work),'done'=>0,'running'=>true,'last'=>'Queued '.count($work).' items','job_id'=>wp_generate_uuid4(),'started'=>current_time('timestamp')];
        set_transient(self::STATE_KEY, $state, HOUR_IN_SECONDS);
        set_transient(self::STATE_KEY.'_'.$state['job_id'], $work, 6*HOUR_IN_SECONDS);
        do_action('buzzsaw_run_batch', $state['job_id']);
        if (!wp_next_scheduled('buzzsaw_run_batch',[$state['job_id']])) wp_schedule_single_event(time()+5,'buzzsaw_run_batch',[$state['job_id']]);
        return ['ok'=>true,'job_id'=>$state['job_id']];
    }

    public static function progress(){ return get_transient(self::STATE_KEY) ?: ['total'=>0,'done'=>0,'running'=>false,'last'=>'Idle']; }
    public static function cancel(){ $s=get_transient(self::STATE_KEY); if($s&&!empty($s['job_id'])) delete_transient(self::STATE_KEY.'_'.$s['job_id']); delete_transient(self::STATE_KEY); return ['ok'=>true]; }

    protected static function build_worklist(){
        $company = bs_fs_segment(get_bloginfo('name'));
        $ids = get_posts(['post_type'=>'product','post_status'=>'publish','fields'=>'ids','posts_per_page'=>-1,'no_found_rows'=>true]);
        $work = [];
        foreach ($ids as $pid){
            $product = wc_get_product($pid);
            $title = bs_fs_segment(get_the_title($pid) ?: ('product-'.$pid));
            $dir = $company.'/'.$title;

            // 1) Featured image
            if ($thumb = get_post_thumbnail_id($pid)){
                $path = get_attached_file($thumb);
                if (is_readable($path)) $work[] = self::make_local($dir, $path);
            }

            // 2) Variation images (distinct colors)
            foreach (bs_collect_color_images($product) as $color => $src){
                if (!$src) continue;
                $item = is_readable($src) ? self::make_local($dir, $src) : self::make_url($dir, $src);
                // prefix filename with color to avoid accidental collisions
                $item['name'] = bs_fs_segment($color).'--'.$item['name'];
                $work[] = $item;
            }

            // 3) Art fields (legacy + {Print Location})
            foreach (bs_collect_art_urls($pid) as $url){
                $local = self::maybe_local_path_from_url($url);
                $work[] = ($local && is_readable($local)) ? self::make_local($dir,$local) : self::make_url($dir,$url);
            }
        }
        // de-dupe by dir+name
        $seen=[]; $out=[];
        foreach ($work as $w){ $k=$w['dir'].'|'.$w['name']; if(!isset($seen[$k])){ $seen[$k]=1; $out[]=$w; } }
        return $out;
    }

    protected static function make_local($dir,$path){ return ['dir'=>$dir,'name'=>basename($path),'size'=>@filesize($path)?:0,'path'=>$path,'is_url'=>false]; }
    protected static function make_url($dir,$url){
        $name = basename(parse_url($url, PHP_URL_PATH) ?: 'remote-file'); if(!$name) $name='remote-file';
        return ['dir'=>$dir,'name'=>$name,'size'=>0,'path'=>$url,'is_url'=>true];
    }
    protected static function maybe_local_path_from_url($url){
        $u = wp_get_upload_dir(); if(!empty($u['baseurl']) && strpos($url,$u['baseurl'])===0){ $rel = substr($url, strlen($u['baseurl'])); return $u['basedir'].$rel; }
        return null;
    }

    public static function run_batch($job_id){
        $state = get_transient(self::STATE_KEY);
        if(!$state || empty($state['running']) || $state['job_id']!==$job_id) return;
        $work = get_transient(self::STATE_KEY.'_'.$job_id);
        if(!$work){ $state['running']=false; $state['last']='Done'; set_transient(self::STATE_KEY,$state,HOUR_IN_SECONDS); return; }
        $chunk = array_splice($work,0,6);
        foreach($chunk as $item){ $state['last']=self::ensure_local_file($item); $state['done']++; set_transient(self::STATE_KEY,$state,HOUR_IN_SECONDS); }
        set_transient(self::STATE_KEY.'_'.$job_id,$work,6*HOUR_IN_SECONDS);
        if($work) wp_schedule_single_event(time()+5,'buzzsaw_run_batch',[$job_id]); else { $state['running']=false; $state['last']='Done'; set_transient(self::STATE_KEY,$state,HOUR_IN_SECONDS); }
    }

    protected static function ensure_local_file($item){
        $base = rtrim(BUZZSAW_BASE_PATH,'/'); $dest_dir = $base.'/'.$item['dir']; if(!wp_mkdir_p($dest_dir)) return 'mkdir failed: '.$dest_dir;
        $dest = $dest_dir.'/'.$item['name'];
        if (file_exists($dest) && $item['size']>0 && filesize($dest)===(int)$item['size']) return 'Skip (same): '.$dest;
        if ($item['is_url']){
            $head = wp_remote_head($item['path'],['timeout'=>15]); $rs=0; if(!is_wp_error($head)){ $len=wp_remote_retrieve_header($head,'content-length'); if($len) $rs=(int)$len; }
            if(file_exists($dest) && $rs>0 && filesize($dest)===$rs) return 'Skip (same): '.$dest;
            $resp = wp_remote_get($item['path'],['timeout'=>45]); if(is_wp_error($resp)) return 'Fetch failed: '.$resp->get_error_message();
            $code = wp_remote_retrieve_response_code($resp); $body = wp_remote_retrieve_body($resp);
            if($body==='' && $code>=400) return 'Fetch HTTP '.$code;
            return file_put_contents($dest,$body)!==false ? 'Fetched: '.$dest : 'Write failed: '.$dest;
        }
        if(!is_readable($item['path'])) return 'Read failed: '.$item['path'];
        return @copy($item['path'],$dest) ? 'Copied: '.$dest : 'Copy failed: '.$item['path'].' -> '.$dest;
    }
}
