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
