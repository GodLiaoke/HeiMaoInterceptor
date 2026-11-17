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

    /** @return array{pin:string,authorized:bool,expires_in:int,expire_at:int,card_expire_at:int,card:?string} */
    public static function status(string $pin): array
    {
        $pdo = Database::pdo();
        $st = $pdo->prepare('SELECT p.pin, p.authorized_until, c.code, c.status AS card_status, c.expire_at AS card_expire_at
                             FROM pins p LEFT JOIN cards c ON c.id = p.card_id
                             WHERE p.pin = ?');
        $st->execute([$pin]);
        $row = $st->fetch();
        $now = time();
        if (!$row) {
            return ['pin' => $pin, 'authorized' => false, 'expires_in' => 0,
                    'expire_at' => 0, 'authorized_until' => 0,
                    'card_expire_at' => 0, 'card_seconds_left' => 0, 'card_status' => 0,
                    'card' => null];
        }
        $until = (int) $row['authorized_until'];
        $left = max(0, $until - $now);
        $cardExpire = (int) ($row['card_expire_at'] ?? 0);
        return [
            'pin'                => $pin,
            'authorized'         => $left > 0,
            'expires_in'         => $left,
            /* expire_at 保持旧语义：本次窗口结束时间（老客户端兼容） */
            'expire_at'          => $until,
            'authorized_until'   => $until,
            'card_expire_at'     => $cardExpire,
            'card_seconds_left'  => max(0, $cardExpire - $now),
            'card_status'        => (int) ($row['card_status'] ?? 0),
            'expire_text'        => $left > 0 ? date('Y-m-d H:i:s', $until) : '',
            'card'               => $left > 0 ? substr((string) $row['code'], 0, 4) . '****' : null,
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
