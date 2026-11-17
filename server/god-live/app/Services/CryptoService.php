<?php
declare(strict_types=1);

/**
 * God 卡密验证系统 · v2 加密协议
 *
 *   key      : storage/config.php 里的 api_key（32 字节 hex）
 *   请求签名 : sig = hmac_sha256(key, "req|路径|pin|dev|ts|nonce") 前 32 位 hex
 *   防重放   : ts 与本机时间相差 ≤120s，nonce 一次性（nonces 表）
 *   响应加密 : iv 为 16 位 hex 随机数，密文 = 明文 XOR keystream(key, iv)
 *              keystream = hmac_sha256(key, "enc|iv|0") || hmac(...|1) || ...
 *              外层再带 s = hmac(key, "r|iv|密文|nonce") 前 32 位 hex
 *   授权令牌 : base64url(payload).hmac(key,"t|payload") —— 客户端可离线验签，
 *              payload 里带 pin / 设备号 / 到期时间 / 功能清单，客户端自己改不了
 */
final class Crypto
{
    private static ?string $keyBytes = null;

    public static function key(): string
    {
        if (self::$keyBytes !== null) {
            return self::$keyBytes;
        }
        $hex = (string) Config::get('api_key', '');
        if (strlen($hex) < 32 || !preg_match('/^[0-9a-f]+$/i', $hex)) {
            throw new RuntimeException('api_key missing or invalid');
        }
        return self::$keyBytes = hex2bin($hex);
    }

    public static function mac(string $msg): string
    {
        return hash_hmac('sha256', $msg, self::key(), true);
    }

    /** 32 位 hex 短签名 */
    public static function sign(string $msg): string
    {
        return substr(bin2hex(self::mac($msg)), 0, 32);
    }

    public static function check(string $msg, string $sig): bool
    {
        return hash_equals(self::sign($msg), strtolower($sig));
    }

    private static function keystream(string $iv, int $len): string
    {
        $out = '';
        $i = 0;
        while (strlen($out) < $len) {
            $out .= hash_hmac('sha256', 'enc|' . $iv . '|' . $i, self::key(), true);
            $i++;
        }
        return substr($out, 0, $len);
    }

    /** 响应体加密：payload -> {iv,d,s} */
    public static function box(array $payload, string $nonce): array
    {
        $plain = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (!is_string($plain)) {
            $plain = '{"ok":false,"error":"encode_error"}';
        }
        $iv = bin2hex(random_bytes(8));
        $ct = $plain ^ self::keystream($iv, strlen($plain));
        $d  = bin2hex($ct);
        return ['v' => 2, 'iv' => $iv, 'd' => $d, 's' => self::sign('r|' . $iv . '|' . $d . '|' . $nonce)];
    }

    /** 校验请求签名 + 防重放；成功返回 [pin, dev, nonce]，失败 null */
    public static function checkRequest(string $path, array $b): ?array
    {
        $pin = PinService::normalise((string) ($b['pin'] ?? ''));
        $dev = strtolower((string) ($b['dev'] ?? ''));
        $ts  = (int) ($b['ts'] ?? 0);
        $n   = strtolower((string) ($b['n'] ?? ''));
        $sig = strtolower((string) ($b['sig'] ?? ''));

        if (!PinService::valid($pin)) {
            return null;
        }
        if (!preg_match('/^[0-9a-f]{8,32}$/', $dev)) {
            return null;
        }
        if (!preg_match('/^[0-9a-f]{16}$/', $n) || !preg_match('/^[0-9a-f]{32}$/', $sig)) {
            return null;
        }
        $now = time();
        if (abs($now - $ts) > 120) {
            Log::file('secure', 'ts drift pin=' . $pin . ' ts=' . $ts . ' now=' . $now);
            return null;
        }
        if (!self::check('req|' . $path . '|' . $pin . '|' . $dev . '|' . $ts . '|' . $n, $sig)) {
            Log::file('secure', 'bad sig pin=' . $pin . ' path=' . $path);
            return null;
        }
        if (!Nonce::take($n, Http::ip())) {
            Log::file('secure', 'replay pin=' . $pin . ' nonce=' . $n);
            return null;
        }
        return ['pin' => $pin, 'dev' => $dev, 'n' => $n];
    }

    /** 授权令牌：客户端可离线验签，内容改一位就失效 */
    public static function token(string $pin, string $dev, int $expireAt, array $feats): string
    {
        $payload = json_encode([
            'p' => $pin,
            'd' => $dev,
            'x' => $expireAt,
            'f' => $feats,
            'i' => time(),
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        return rtrim(strtr(base64_encode($payload), '+/', '-_'), '=') . '.' . self::sign('t|' . $payload);
    }

    /** 打包一份「授权状态」响应（handshake / card 共用） */
    public static function statusBox(string $pin, string $dev, string $nonce): array
    {
        $st = PinService::status($pin);
        $feats = $st['authorized'] ? self::features($pin) : [];
        return self::box([
            'ok'          => true,
            'authorized'  => $st['authorized'],
            'pin'         => $pin,
            'expire_at'   => (int) $st['expire_at'],
            'expires_in'  => (int) $st['expires_in'],
            'expire_text' => (string) ($st['expire_text'] ?? ''),
            'card'        => $st['card'],
            'feats'       => $feats,
            'token'       => $st['authorized'] ? self::token($pin, $dev, (int) $st['expire_at'], $feats) : '',
            'server_time' => time(),
        ], $nonce);
    }

    /** 功能清单：服务端说了算，客户端只照着开关走 */
    public static function features(string $pin): array
    {
        $base = ['core', 'aim', 'espl', 'skin', 'drv'];
        $pdo  = Database::pdo();
        $st   = $pdo->prepare('SELECT c.note FROM pins p LEFT JOIN cards c ON c.id = p.card_id WHERE p.pin = ?');
        $st->execute([$pin]);
        $note = strtolower((string) $st->fetchColumn());
        /* 卡密备注里写 plan:basic / plan:pro 就能分档，默认全开 */
        if (str_contains($note, 'plan:basic')) {
            return ['core', 'aim'];
        }
        if (str_contains($note, 'plan:pro')) {
            return ['core', 'aim', 'espl', 'skin'];
        }
        return $base;
    }
}

/**
 * 一次性随机数，防重放
 *
 * 用文件独占创建（O_EXCL）判定重复：同一个 nonce 第二次创建必失败，
 * 天然原子，且不占用数据库写锁（并发时不会再 database is locked）。
 */
final class Nonce
{
    public static function take(string $n, string $ip = ''): bool
    {
        if (!preg_match('/^[0-9a-f]{16,40}$/', $n)) {
            return false;
        }
        $now = time();
        $dir = APP_STORAGE . '/cache/nonce';
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }

        $file = $dir . '/' . $n;
        $fh = @fopen($file, 'x');          /* x = 独占创建，已存在则失败 */
        if ($fh === false) {
            return false;                   /* 文件已存在 = 重放 */
        }
        fwrite($fh, $ip . '|' . $now);
        fclose($fh);
        @chmod($file, 0640);

        if (random_int(1, 50) === 1) {
            foreach ((array) @glob($dir . '/*') as $f) {
                if (@filemtime($f) < $now - 900) {
                    @unlink($f);
                }
            }
        }
        return true;
    }
}
