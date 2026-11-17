<?php
declare(strict_types=1);

/**
 * v3 全链路加密通道
 *
 * 目标：抓包只看到一串随机字节，改一个字节直接验签失败。
 *
 * 请求体（JSON，为了兼容老客户端，没有 v=3 就走明文）：
 *   {
 *     "v":   3,
 *     "p":   "12345678",          // 设备码，用于派生会话密钥
 *     "ts":  1794900000,          // 秒级时间戳，±300 秒内有效
 *     "n":   "32 位 hex",         // 一次性随机数，服务端 nonce 表去重（防重放）
 *     "e":   "base64",            // AES-256-GCM(iv12 + 密文 + tag16)
 *     "sig": "64 位 hex"          // HMAC-SHA256
 *   }
 *
 * 密钥体系（两边都用 HKDF-SHA256，主密钥 = storage/config.php 的 api_key）：
 *   请求密钥 = HKDF(master, salt="heimao-v3-salt", info="heimao-v3-req")
 *   响应密钥 = HKDF(master, salt="heimao-v3-salt", info="heimao-v3-res")
 *   AAD      = nonce（二进制 16 字节）
 *
 * 签名串：
 *   请求 sig = HMAC(master, "v3|路径|设备码|ts|nonce|sha256hex(密文)")
 *   响应 sig = HMAC(master, "v3r|nonce|sha256hex(密文)")
 *
 * 主密钥只存在服务端配置和客户端二进制里，抓包拿不到；
 * 每条请求带一次性 nonce，重放直接拒。
 */
final class SecureV3
{
    public const VERSION = 3;

    private const SALT     = 'heimao-v3-salt';
    private const INFO_REQ = 'heimao-v3-req';
    private const INFO_RES = 'heimao-v3-res';
    private const TS_SKEW  = 300;   // 允许的时钟偏差（秒）

    /** @var string|null */
    private static $master = null;

    /** 本次请求是否走加密通道 */
    /** @var bool */
    public static $active = false;
    /** 本次请求的设备码 */
    /** @var string|null */
    public static $pin = null;
    /** 本次请求的 nonce（hex） */
    /** @var string|null */
    public static $nonce = null;

    public static function master(): string
    {
        if (self::$master !== null) {
            return self::$master;
        }
        $hex = (string) Config::get('api_key', '');
        if (strlen($hex) < 32 || !preg_match('/^[0-9a-f]+$/i', $hex)) {
            throw new RuntimeException('v3 master key missing');
        }
        return self::$master = hex2bin($hex);
    }

    public static function reqKey(): string
    {
        return hash_hkdf('sha256', self::master(), 32, self::INFO_REQ, self::SALT);
    }

    public static function resKey(): string
    {
        return hash_hkdf('sha256', self::master(), 32, self::INFO_RES, self::SALT);
    }

    public static function sign(string $msg): string
    {
        return hash_hmac('sha256', $msg, self::master());
    }

    /** AES-256-GCM 封装，返回 base64(iv + ct + tag) */
    public static function seal(string $plain, string $key, string $aad): string
    {
        $iv  = random_bytes(12);
        $tag = '';
        $ct  = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, $aad, 16);
        if ($ct === false) {
            throw new RuntimeException('v3 seal failed');
        }
        return base64_encode($iv . $ct . $tag);
    }

    /** 解开 base64(iv + ct + tag) */
    public static function open(string $b64, string $key, string $aad): ?string
    {
        $raw = base64_decode($b64, true);
        if ($raw === false || strlen($raw) < 29) {
            return null;
        }
        $iv  = substr($raw, 0, 12);
        $tag = substr($raw, -16);
        $ct  = substr($raw, 12, strlen($raw) - 28);
        $pt  = openssl_decrypt($ct, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, $aad);
        return $pt === false ? null : $pt;
    }

    /**
     * 尝试解包加密请求。
     * 不是 v3 请求返回 null（调用方回落到明文解析）。
     * 是 v3 但校验不过 → 直接输出错误并退出（绝不继续处理）。
     */
    public static function unwrap(array $raw, string $path): ?array
    {
        if ((int) ($raw['v'] ?? 0) !== self::VERSION) {
            return null;
        }

        $pin = PinService::normalise((string) ($raw['p'] ?? ''));
        $ts  = (int) ($raw['ts'] ?? 0);
        $n   = strtolower((string) ($raw['n'] ?? ''));
        $e   = (string) ($raw['e'] ?? '');
        $sig = strtolower((string) ($raw['sig'] ?? ''));

        if (!PinService::valid($pin)) {
            self::reject('bad_pin');
        }
        if (!preg_match('/^[0-9a-f]{32}$/', $n)) {
            self::reject('bad_nonce');
        }
        if ($e === '' || !preg_match('/^[0-9a-f]{64}$/', $sig)) {
            self::reject('bad_envelope');
        }
        $now = time();
        if (abs($now - $ts) > self::TS_SKEW) {
            Log::file('secure', 'v3 ts drift path=' . $path . ' ts=' . $ts . ' now=' . $now);
            self::reject('stale_request');
        }

        $msg = 'v3|' . $path . '|' . $pin . '|' . $ts . '|' . $n . '|' . hash('sha256', $e);
        if (!hash_equals(self::sign($msg), $sig)) {
            /*
             * 兼容历史客户端：早期版本签名串里带了前导斜杠
             * （"v3|/session/renew|…"），而这里 trim 之后是 "session/renew"。
             * 两种形态都接受，避免老包全线 400；签名强度不变——
             * 攻击者既改不了路径也改不了 ts/nonce，两种拼法都得有主密钥才能算出来。
             */
            $alt = 'v3|/' . $path . '|' . $pin . '|' . $ts . '|' . $n . '|' . hash('sha256', $e);
            if (!hash_equals(self::sign($alt), $sig)) {
                Log::file('secure', 'v3 bad sig path=' . $path . ' pin=' . $pin);
                self::reject('bad_signature');
            }
        }

        $nonceBin = hex2bin($n);
        $plain    = self::open($e, self::reqKey(), $nonceBin);
        if ($plain === null) {
            Log::file('secure', 'v3 bad cipher path=' . $path . ' pin=' . $pin);
            self::reject('bad_cipher');
        }

        /* 防重放：同一个 nonce 只能用一次 */
        if (!Nonce::take($n, Http::ip())) {
            Log::file('secure', 'v3 replay path=' . $path . ' pin=' . $pin);
            self::reject('replay');
        }

        $data = json_decode($plain, true);
        if (!is_array($data)) {
            $data = [];
        }

        self::$active = true;
        self::$pin    = $pin;
        self::$nonce  = $n;

        /* pin 以请求头里的为准，防止明文段被篡改后覆盖 */
        $data['pin'] = $pin;
        return $data;
    }

    /** 把响应体装进加密信封 */
    public static function sealResponse(array $payload): array
    {
        $plain = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (!is_string($plain)) {
            $plain = '{"ok":false,"error":"encode_error"}';
        }
        $n   = (string) self::$nonce;
        $e   = self::seal($plain, self::resKey(), (string) hex2bin($n));
        $sig = self::sign('v3r|' . $n . '|' . hash('sha256', $e));

        return ['v' => self::VERSION, 'n' => $n, 'e' => $e, 'sig' => $sig];
    }

    /** 加密通道自身的错误：固定明文返回（不带任何业务信息） */
    private static function reject(string $error): void
    {
        Http::json(['ok' => false, 'error' => $error, 'secure' => 3], 400);
    }
}

/**
 * 统一请求参数入口
 * 加密请求读解密后的内容，明文请求读 JSON body + query string。
 * 全站只允许从这里拿参数，避免某个端点漏改又变成明文。
 */
final class Req
{
    private static $params = [];
    private static $ready = false;

    public static function init(string $path): void
    {
        if (self::$ready) {
            return;
        }
        $raw = Http::body();          // php://input 只能读一次，这里读完全程复用
        $query = $_GET ?: [];

        $v3 = null;
        try {
            $v3 = SecureV3::unwrap($raw, $path);
        } catch (Throwable $e) {
            Log::file('secure', 'v3 unwrap fatal: ' . $e->getMessage());
            Http::json(['ok' => false, 'error' => 'server_error'], 500);
        }

        if ($v3 !== null) {
            self::$params = $v3;
        } else {
            self::$params = $raw + $query;
        }
        self::$ready = true;
    }

    public static function p(string $key, $def = null)
    {
        return self::$params[$key] ?? $def;
    }

    public static function all(): array
    {
        return self::$params;
    }

    public static function isSecure(): bool
    {
        return SecureV3::$active;
    }
}

/**
 * 统一响应出口：加密请求就回加密信封，明文请求照旧回 JSON。
 */
final class Res
{
    public static function json($data, int $status = 200): void
    {
        if (SecureV3::$active) {
            if (!is_array($data)) {
                $data = ['ok' => false, 'error' => 'encode_error'];
            }
            $box = SecureV3::sealResponse($data);
            http_response_code($status);
            header('Content-Type: application/json; charset=utf-8');
            header('X-Content-Type-Options: nosniff');
            header('Cache-Control: no-store');
            echo json_encode($box, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            exit;
        }
        Http::json($data, $status);
    }

    public static function abort(int $status, string $error): void
    {
        self::json(['ok' => false, 'error' => $error], $status);
    }

    /**
     * 二进制下发（规则包）：加密请求封装成 base64 放进加密 JSON；
     * 明文请求保留原来的 octet-stream 行为，老客户端不受影响。
     */
    public static function binary(string $blob, array $meta = []): void
    {
        if (SecureV3::$active) {
            self::json($meta + [
                'ok'      => true,
                'blob'    => base64_encode($blob),
                'bytes'   => strlen($blob),
            ]);
        }
        header('Content-Type: application/octet-stream');
        header('Content-Length: ' . strlen($blob));
        foreach ($meta as $k => $v) {
            if (is_scalar($v)) {
                header('X-' . str_replace('_', '-', $k) . ': ' . $v);
            }
        }
        header('Cache-Control: no-store');
        echo $blob;
        exit;
    }
}
