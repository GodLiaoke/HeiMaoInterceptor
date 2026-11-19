<?php
declare(strict_types=1);

/**
 * v4 通道：裸密文（抓包看不到任何结构）
 *
 * v3 的问题不是不安全，是「太明显」：
 *   {"v":3,"n":"…","e":"…","sig":"…"} 一眼就能看出这是加密信封，
 *   字段名还直接告诉对方哪里是 nonce、哪里是密文、哪里是签名。
 *
 * v4 把请求和响应都压成一段纯二进制，没有任何 JSON、没有任何自定义头：
 *   请求体 = iv(12) || AES-256-GCM 密文 || tag(16)
 *   响应体 = iv(12) || AES-256-GCM 密文 || tag(16)
 *
 * 密钥（每条请求各不相同的派生密钥）：
 *   请求密钥 = HKDF-SHA512(master, salt=iv, info="hm4/req", 32B)
 *   响应密钥 = HKDF-SHA512(master, salt=请求iv, info="hm4/res", 32B)
 * 签名（明文里带着，外层看不到）：
 *   sig = HMAC-SHA512(master, "h4|路由|设备码|ts|ivhex|sha256(参数规范串)")
 *   参数规范串 = 所有业务参数按 key 字典序拼成 "k=v"，用 0x1F 连接
 *   （不覆盖密文本体，避免签名与密文互相依赖；密文完整性由 GCM tag + AAD 保证）
 * AAD：
 *   请求 = "hm4|路由|ts"   响应 = "hm4r|请求ivhex"
 *
 * 也就是说：改一个字节、换一个路由、晚 5 分钟重放，全都过不去。
 * 老客户端（v3）完全不受影响，两条通道并行。
 */
final class SecureV4
{
    public const VERSION   = 4;
    private const TS_SKEW  = 900;   // 放宽到 15 分钟：设备时间不准时先回错误让客户端校时重发，别整条通道挡死
    private const INFO_REQ = 'hm4/req';
    private const INFO_RES = 'hm4/res';

    /** @var bool */
    public static $active = false;
    /** @var string|null */
    public static $pin = null;
    /** @var string 请求 iv 的 hex（响应密钥与 AAD 都用它） */
    public static $ivHex = '';

    private static function master(): string
    {
        return SecureV3::master();
    }

    private static function derive(string $info, string $salt): string
    {
        return hash_hkdf('sha512', self::master(), 32, $info, $salt);
    }

    /** 用派生密钥解密一段 iv||ct||tag，失败返回 null */
    private static function openBlob(string $blob, string $key, string $aad): ?string
    {
        if (strlen($blob) < 29) {
            return null;
        }
        $iv  = substr($blob, 0, 12);
        $tag = substr($blob, -16);
        $ct  = substr($blob, 12, strlen($blob) - 28);
        $pt  = openssl_decrypt($ct, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, $aad);
        return $pt === false ? null : $pt;
    }

    /** 封装一段 iv||ct||tag */
    private static function sealBlob(string $plain, string $key, string $aad): string
    {
        $iv  = random_bytes(12);
        $tag = '';
        $ct  = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, $aad, 16);
        if ($ct === false) {
            throw new RuntimeException('v4 seal failed');
        }
        return $iv . $ct . $tag;
    }

    /**
     * 解包 v4 请求。
     * 不是 v4（内容对不上）返回 null，调用方回落到 v3 / 明文。
     * 是 v4 但校验不过 → 直接拒绝，绝不继续处理。
     */
    public static function unwrap(string $path): ?array
    {
        $blob = file_get_contents('php://input', false, null, 0, 4 * 1024 * 1024);
        if (!is_string($blob) || strlen($blob) < 29) {
            return null;
        }
        $iv = substr($blob, 0, 12);
        $ivHex = bin2hex($iv);
        /* 先记下 iv：后面任何一步拒绝，都能用同一把响应密钥把错误加密回去，
           客户端就能读懂「时间不准 / 重放 / 签名不对」这些具体原因 */
        self::$ivHex = $ivHex;
        /* AAD 绑定「路由 + 这条请求的 iv」：
           同一段密文挪到别的接口、被替换到另一条请求里，都解不开。
           时间戳在密文内，由签名覆盖，改一个字符签名就废。 */
        $aad = 'hm4|' . $path . '|' . $ivHex;
        $key = self::derive(self::INFO_REQ, $iv);
        $plain = self::openBlob($blob, $key, $aad);
        if ($plain === null) {
            return null;
        }
        $data = json_decode((string) $plain, true);
        if (!is_array($data)) {
            return null;
        }
        $ts = (int) ($data['t'] ?? 0);

        $pin = PinService::normalise((string) ($data['p'] ?? ''));
        $nonce = strtolower((string) ($data['n'] ?? $ivHex));
        $sig = strtolower((string) ($data['s'] ?? ''));
        $route = (string) ($data['r'] ?? '');

        if (!PinService::valid($pin) || $route !== $path) {
            self::reject('bad_v4');
        }
        if (abs(time() - $ts) > self::TS_SKEW) {
            Log::file('secure', 'v4 ts drift path=' . $path . ' ts=' . $ts . ' now=' . time());
            /* 把服务端当前时间一起回给客户端（仍在密文里）：
               客户端据此换算本机时钟偏移后重发一次，设备时间不准也不至于整条通道用不了 */
            self::reject('stale_request', ['now' => time()]);
        }
        if (!preg_match('/^[0-9a-f]{128}$/', $sig)) {
            self::reject('bad_v4');
        }

        $msg = 'h4|' . $path . '|' . $pin . '|' . $ts . '|' . $ivHex . '|'
             . hash('sha256', self::canonical($data['d'] ?? []));
        $expect = hash_hmac('sha512', $msg, self::master());
        if (!hash_equals($expect, $sig)) {
            Log::file('secure', 'v4 bad sig path=' . $path . ' pin=' . $pin);
            self::reject('bad_signature');
        }
        if (!Nonce::take($nonce, Http::ip())) {
            Log::file('secure', 'v4 replay path=' . $path . ' pin=' . $pin);
            self::reject('replay');
        }

        $params = $data['d'] ?? [];
        if (!is_array($params)) {
            $params = [];
        }
        $params['pin'] = $pin;

        self::$active = true;
        self::$pin    = $pin;
        self::$ivHex  = $ivHex;
        return $params;
    }

    /**
     * 参数规范串：key 字典序，k=v 用 0x1F 连接。
     * 客户端与服务端必须逐字一致，否则签名对不上。
     */
    public static function canonical($params): string
    {
        if (!is_array($params)) {
            return '';
        }
        $keys = array_keys($params);
        sort($keys, SORT_STRING);
        $pairs = [];
        foreach ($keys as $k) {
            $v = $params[$k];
            if (is_bool($v)) {
                $v = $v ? '1' : '0';
            } elseif (is_array($v) || is_object($v)) {
                $v = json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }
            $pairs[] = (string) $k . '=' . (string) $v;
        }
        return implode("\x1f", $pairs);
    }

    /** 把业务响应装成裸密文 */
    public static function sealResponse(array $payload): string
    {
        $plain = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (!is_string($plain)) {
            $plain = '{"ok":false,"error":"encode_error"}';
        }
        $salt = (string) hex2bin(self::$ivHex);
        $key  = self::derive(self::INFO_RES, $salt);
        return self::sealBlob($plain, $key, 'hm4r|' . self::$ivHex);
    }

    /**
     * 通道自身错误
     *
     * 只要拿得到请求 iv，就用响应密钥把错误加密回去 —— 抓包看到的仍是随机字节，
     * 客户端也能把具体原因（时间不准 / 重放 / 签名不对）翻译成人话。
     * 连 iv 都没有时才回明文（客户端据此判定通道不可用）。
     */
    private static function reject(string $error, array $extra = []): void
    {
        if (self::$ivHex !== '') {
            try {
                self::$active = true;
                $blob = self::sealResponse(['ok' => false, 'error' => $error] + $extra);
                http_response_code(200);
                header('Content-Type: application/octet-stream');
                header('Content-Length: ' . strlen($blob));
                header('Cache-Control: no-store');
                echo $blob;
                exit;
            } catch (Throwable $e) {
                Log::file('secure', 'v4 reject seal failed: ' . $e->getMessage());
            }
        }
        Http::json(['ok' => false, 'error' => $error, 'secure' => 4], 400);
    }
}
