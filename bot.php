<?php
declare(strict_types=1);

/**
 * 黑猫公益拦截 · 卡密生成接口（单用途版）
 *
 * 只做一件事：生成卡密。
 * 查卡 / 作废 / 续期 / 踢设备 / 公告 / 统计 等接口已全部移除（后台管理页照旧可用）。
 *
 * ---------------------------------------------------------------
 * 调用方式
 * ---------------------------------------------------------------
 * POST https://ios.ouovo.cc/bot.php
 * Header:
 *   X-Api-Key: <storage/bot_config.php 里的 api_key>
 *   Content-Type: application/json
 * Body（全部可选）:
 * {
 *   "count":   10,          // 生成数量 1 ~ 500，默认 1
 *   "days":    7,           // 有效天数 1 ~ 30，默认 7（也可以用 "seconds": 604800）
 *   "charset": "std",       // std(无歧义) | digit(纯数字) | alpha(纯字母) | full
 *   "batch":   "HM20261117",// 批次号，留空自动 ZK+日期
 *   "note":    "公益发放"    // 备注，最长 110 字
 * }
 *
 * 返回:
 * {
 *   "ok": true, "created": 10, "duration_sec": 604800, "duration_days": 7,
 *   "charset": "std", "batch": "HM20261117",
 *   "codes": ["XXXX-XXXX-XXXX-XXXX", ...]
 * }
 *
 * ---------------------------------------------------------------
 * 签名（可选，默认关闭）
 * ---------------------------------------------------------------
 * 在 storage/bot_config.php 里加一行 'require_signature' => true 即开启，开启后必须带:
 *   X-Timestamp: 秒级时间戳（±300 秒内有效）
 *   X-Sign: hash_hmac('sha256', ts."\n".METHOD."\n".action."\n".rawBody, secret)
 *   action 为 cards.generate 或 health
 *
 * 其它可选项（写进 storage/bot_config.php 即可）:
 *   'allowed_ips' => ['1.2.3.4', '5.6.7.*']   // 白名单，空数组=不限制
 *   'max_count'   => 500                      // 单次最多生成
 *   'max_days'    => 30                       // 单张最长天数
 *   'default_days'=> 7                        // 不传时默认天数
 */

require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/Services/CardService.php';

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');
header('Referrer-Policy: no-referrer');

final class CardApi
{
    private const DEFAULTS = [
        'require_signature' => false,
        'time_window'       => 300,
        'allowed_ips'       => [],
        'max_count'         => 500,
        'max_days'          => 30,
        'default_days'      => 7,
    ];

    private const CHARSETS = ['std', 'digit', 'alpha', 'full'];

    private static $cfg = [];

    public static function boot(): void
    {
        $file = APP_STORAGE . '/bot_config.php';
        $base = is_file($file) ? (require $file) : [];
        if (!is_array($base)) {
            $base = [];
        }
        self::$cfg = array_merge(self::DEFAULTS, $base);
    }

    public static function cfg(string $k, $def = null)
    {
        return array_key_exists($k, self::$cfg) ? self::$cfg[$k] : $def;
    }

    public static function json(array $data, int $code = 200): void
    {
        http_response_code($code);
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    public static function fail(string $error, int $code = 400): void
    {
        self::json(['ok' => false, 'error' => $error], $code);
    }

    public static function rawBody(): string
    {
        static $raw = null;
        if ($raw === null) {
            $raw = (string) file_get_contents('php://input');
        }
        return $raw;
    }

    public static function body(): array
    {
        $j = json_decode(self::rawBody(), true);
        if (is_array($j)) {
            return $j;
        }
        return $_POST ?: [];
    }

    public static function action(): string
    {
        $a = trim((string) ($_GET['action'] ?? ''));
        return $a === '' ? 'cards.generate' : $a;
    }

    public static function ip(): string
    {
        foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'REMOTE_ADDR'] as $k) {
            if (!empty($_SERVER[$k])) {
                $v = explode(',', (string) $_SERVER[$k])[0];
                return substr(trim($v), 0, 64);
            }
        }
        return '0.0.0.0';
    }

    public static function apiKey(): string
    {
        $key = trim((string) ($_SERVER['HTTP_X_API_KEY'] ?? ''));
        if ($key !== '') {
            return $key;
        }
        $auth = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
        if (stripos($auth, 'bearer ') === 0) {
            return trim(substr($auth, 7));
        }
        return '';
    }

    private static function ipAllowed(string $ip): bool
    {
        $allow = self::cfg('allowed_ips', []);
        if (!is_array($allow) || $allow === []) {
            return true;
        }
        foreach ($allow as $rule) {
            $rule = trim((string) $rule);
            if ($rule === '') {
                continue;
            }
            if ($rule === $ip) {
                return true;
            }
            if (substr($rule, -1) === '*' && strpos($ip, rtrim($rule, '*')) === 0) {
                return true;
            }
        }
        return false;
    }

    public static function auth(string $action): void
    {
        $expect = (string) self::cfg('api_key', '');
        if ($expect === '') {
            self::fail('api_key_not_configured', 503);
        }

        $key = self::apiKey();
        if ($key === '') {
            self::fail('missing_api_key', 401);
        }
        if (!hash_equals($expect, $key)) {
            self::fail('bad_api_key', 401);
        }

        if (!self::ipAllowed(self::ip())) {
            self::fail('ip_not_allowed', 403);
        }

        if (self::cfg('require_signature')) {
            $secret = (string) self::cfg('secret', '');
            if ($secret === '') {
                self::fail('secret_not_configured', 503);
            }
            $ts  = (string) ($_SERVER['HTTP_X_TIMESTAMP'] ?? '');
            $sig = strtolower(trim((string) ($_SERVER['HTTP_X_SIGN'] ?? '')));
            if ($ts === '' || $sig === '') {
                self::fail('missing_signature', 401);
            }
            if (abs(time() - (int) $ts) > (int) self::cfg('time_window', 300)) {
                self::fail('stale_timestamp', 401);
            }
            $method  = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'POST'));
            $payload = $ts . "\n" . $method . "\n" . $action . "\n" . self::rawBody();
            $expectSig = hash_hmac('sha256', $payload, $secret);
            if (!hash_equals($expectSig, $sig)) {
                self::fail('bad_signature', 401);
            }
        }
    }

    /** 生成卡密 */
    public static function generate(): void
    {
        $b = self::body();

        $maxCount = max(1, (int) self::cfg('max_count', 500));
        $count    = (int) ($b['count'] ?? 1);
        $count    = max(1, min($maxCount, $count));

        $maxSec = max(60, (int) self::cfg('max_days', 30) * 86400);
        if (array_key_exists('seconds', $b)) {
            $seconds = (int) $b['seconds'];
        } elseif (array_key_exists('days', $b)) {
            $seconds = (int) round((float) $b['days'] * 86400);
        } else {
            $seconds = (int) self::cfg('default_days', 7) * 86400;
        }
        $durationSec = max(60, min($maxSec, $seconds));

        $charset = (string) ($b['charset'] ?? 'std');
        if (!in_array($charset, self::CHARSETS, true)) {
            $charset = 'std';
        }

        $batch = trim((string) ($b['batch'] ?? ''));
        if ($batch === '') {
            $batch = 'ZK' . date('Ymd');
        }
        $batch = substr(preg_replace('/[^A-Za-z0-9_\-]/', '', $batch) ?: 'ZK' . date('Ymd'), 0, 32);

        $note = trim((string) ($b['note'] ?? ''));
        if ($note === '') {
            $note = 'api:' . self::ip();
        }
        $note = substr($note, 0, 110);

        $r = CardService::createBatch($count, $durationSec, $batch, $note, 'api', self::ip(), $charset);

        self::json([
            'ok'            => true,
            'created'       => (int) $r['created'],
            'count'         => (int) $r['created'],
            'duration_sec'  => $durationSec,
            'duration_days' => (int) $durationSec % 86400 === 0 ? (int) ($durationSec / 86400) : round($durationSec / 86400, 3),
            'charset'       => $charset,
            'batch'         => $batch,
            'note'          => $note,
            'codes'         => $r['codes'],
            'time'          => time(),
        ]);
    }
}

CardApi::boot();

$method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));

if ($method !== 'POST') {
    CardApi::json([
        'ok'    => false,
        'error' => 'method_not_allowed',
        'hint'  => 'POST JSON to this URL with header X-Api-Key',
    ], 405);
}

$action = CardApi::action();

if ($action !== 'cards.generate' && $action !== 'health') {
    CardApi::fail('unknown_action', 404);
}

CardApi::auth($action);

try {
    if ($action === 'health') {
        CardApi::json([
            'ok'      => true,
            'service' => 'heimao-cardgen',
            'time'    => time(),
            'php'     => PHP_VERSION,
            'signed'  => (bool) CardApi::cfg('require_signature'),
        ]);
    }

    CardApi::generate();
} catch (Throwable $e) {
    Log::file('cardapi', 'error: ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    CardApi::fail('server_error', 500);
}
