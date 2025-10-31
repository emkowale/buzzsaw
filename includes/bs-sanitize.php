<?php
if (!defined('ABSPATH')) exit;

function bs_fs_segment($s){
    $s = wp_strip_all_tags((string)$s);
    $s = html_entity_decode($s, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $s = preg_replace('~[\\/\\\\:\\*\\?"<>\\|\\x00-\\x1F]+~u', '-', $s);
    $s = preg_replace('~\\s+~u', ' ', $s);
    $s = trim($s);              // no character mask → no accidental chop
    if ($s === '') $s = 'untitled';
    return $s;
}
