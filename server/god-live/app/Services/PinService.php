<?php
declare(strict_types=1);

/** 配对码：登记 / 心跳 / 授权状态 */
final class PinService
{
    public static function normalise(string $pin): string
    {
        $pin = preg_replace('/\D/', '', $pin) ?? '';
        return $pin;
    }

    public static function valid(string $pin): bool
    {
        $len = (int) Config::get('pin_len', 8);
        return (bool) preg_match('/^\d{' . $len . '}$/', $pin);
    }

    /**
     * 记录一次访问（首次访问自动登记）
     *
     * 节流：同一个配对码 60 秒内只写一次 last_seen。
     * 客户端每几秒就轮询一次，如果每次都 UPDATE，
     * 高并发下 SQLite 会被这些无意义的写锁顶满。
     */
    public static function touch(string $pin, string $ip, string $ua): void
    {
        $pdo = Database::pdo();
        $now = time();
        try {
            $upd = $pdo->prepare(
                'UPDATE pins SET last_seen = ?, ip = ?
                 WHERE pin = ? AND (last_seen IS NULL OR last_seen < ?)'
            );
            $upd->execute([$now, $ip, $pin, $now - 60]);
            if ($upd->rowCount() > 0) {
                return;
            }
            /* 可能是新设备，也可能是刚更新过：查一下到底在不在 */
            $st = $pdo->prepare('SELECT 1 FROM pins WHERE pin = ?');
            $st->execute([$pin]);
            if ($st->fetchColumn()) {
                return;
            }
            $pdo->prepare('INSERT OR IGNORE INTO pins(pin, first_seen, last_seen, ip, ua) VALUES(?,?,?,?,?)')
                ->execute([$pin, $now, $now, $ip, $ua]);
        } catch (Throwable $e) {
            Log::file('app', 'pin touch: ' . $e->getMessage());
        }
    }

    /**
     * 授权状态 —— 唯一判定走 AuthGate
     * （以前只看窗口 authorized_until，卡密作废后仍然回 authorized=true，
     *   客户端就继续显示「已授权」，但隧道一联网校验就失败、开不起来。）
     *
     * @return array{pin:string,authorized:bool,reason:string,...}
     */
    public static function status(string $pin): array
    {
        $r = AuthGate::evaluate($pin);

        return [
            'pin'                => $pin,
            'authorized'         => $r['authorized'],
            'reason'             => $r['reason'],
            'expires_in'         => $r['expires_in'],
            /* expire_at 保持旧语义：本次窗口结束时间（老客户端兼容） */
            'expire_at'          => $r['authorized_until'],
            'authorized_until'   => $r['authorized_until'],
            'card_expire_at'     => $r['card_expire_at'],
            'card_seconds_left'  => $r['card_seconds_left'],
            'card_status'        => $r['card_status'],
            'expire_text'        => $r['card_expire_at'] > 0
                ? date('Y-m-d H:i:s', $r['card_expire_at'])
                : '',
            'card'               => $r['card'],
            'window'             => (int) Config::get('auth_window_sec', 600),
            'grace'              => (int) Config::get('grace_sec', 300),
            'server_time'        => time(),
        ];
    }

    public static function revoke(string $pin): void
    {
        Database::pdo()->prepare('UPDATE pins SET authorized_until = 0 WHERE pin = ?')
            ->execute([$pin]);
    }

    public static function offlineList(int $limit = 200): array
    {
        $st = Database::pdo()->prepare(
            'SELECT pin, first_seen, last_seen, ip, authorized_until, redeem_count
             FROM pins ORDER BY last_seen DESC LIMIT ?');
        $st->execute([$limit]);
        return $st->fetchAll();
    }
}
