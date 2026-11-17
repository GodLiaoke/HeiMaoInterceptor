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

    /** 记录一次访问（首次访问自动登记） */
    public static function touch(string $pin, string $ip, string $ua): void
    {
        $pdo = Database::pdo();
        $now = time();
        $st = $pdo->prepare('SELECT pin FROM pins WHERE pin = ?');
        $st->execute([$pin]);
        if ($st->fetchColumn()) {
            $pdo->prepare('UPDATE pins SET last_seen = ?, ip = ? WHERE pin = ?')
                ->execute([$now, $ip, $pin]);
        } else {
            $pdo->prepare('INSERT INTO pins(pin, first_seen, last_seen, ip, ua) VALUES(?,?,?,?,?)')
                ->execute([$pin, $now, $now, $ip, $ua]);
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
