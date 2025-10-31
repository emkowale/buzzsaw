<?php
if (!defined('ABSPATH')) exit;

/** distinct color → image path/url (one per color) */
function bs_collect_color_images($product){
    if (!$product || !$product->is_type('variable')) return [];
    $out = [];
    foreach ($product->get_children() as $vid){
        $v = wc_get_product($vid); if (!$v) continue;
        $atts = (array)$v->get_attributes();
        $color = $atts['attribute_pa_color'] ?? $atts['attribute_color'] ?? '';
        $color = is_string($color) ? trim($color) : '';
        $img_id = method_exists($v,'get_image_id') ? $v->get_image_id() : 0;
        if (!$color || !$img_id || isset($out[$color])) continue;
        $path = get_attached_file($img_id);
        $out[$color] = is_readable($path) ? $path : (wp_get_attachment_url($img_id) ?: '');
    }
    return array_filter($out);
}

/**
 * Collect Original Art URLs:
 * - legacy: key exactly "original-art"
 * - newer: ANY key that starts with "Original Art" (e.g., "Original Art Front", "Original Art Back", ...).
 */
function bs_collect_art_urls($pid){
    $urls = [];

    // legacy
    $legacy = trim((string)get_post_meta($pid, 'original-art', true));
    if ($legacy) $urls[] = $legacy;

    // newer
    foreach (get_post_meta($pid) as $key => $vals){
        if (!preg_match('/^original\\s*art\\b/i', (string)$key)) continue;
        foreach ((array)$vals as $v){
            $u = trim((string)$v);
            if ($u !== '') $urls[] = $u;
        }
    }

    // de-dupe by absolute string match
    return array_values(array_unique($urls));
}
