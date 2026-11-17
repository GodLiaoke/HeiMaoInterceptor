<?php
declare(strict_types=1);

/**
 * 授权会话：卡密绑定 + 在线校验窗口 + 续期
 *
 * 关键区分（之前把两者混成一个字段，导致「卡密有效却显示未授权」）：
 *   cards.expire_at       卡密本身的到期时间（天/月/年，长期）
 *   pins.authorized_until 本次在线校验的窗口（几分钟，靠客户端定期续期）
 *
 * 窗口只是「这台设备最近还有没有在联网校验」的凭证，
 * 不能用它代表卡密到期，也不能因为它过期就判定卡密失效。
 */
final class SessionService
{
    /** 在线校验窗口（秒） */
    public static function window(): int
    {
        $w = (int) Config::get('auth_window_sec', 600);
        if ($w < 120) { $w = 120; }
        if ($w > 86400) { $w = 86400; }
        return $w;
    }

    /** 断网宽限（秒）：客户端拿不到续期时的容忍时间 */
    public static function grace(): int
    {
        $g = (int) Config::get('grace_sec', 300);
        return $g < 0 ? 0 : $g;
    }

    /**
     * 把卡密绑定到配对码上。
     * - 首次兑换：原子绑定，卡密从这一刻开始计时
     * - 同设备再次兑换：直接通过，只续窗口
     * - 已绑定到别的设备：返回 card_bound（不再含糊成 card_expired）
     *
     * @return array{ok:bool,error?:string,card?:array}
     */
    public static function bind(string $pin, string $rawCode, string $ip, string $ua): array
    {
        $code = CardService::normalise($rawCode);
        if (!preg_match('/^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$/', $code)) {
            return ['ok' => false, 'error' => 'card_format'];
        }

        $pdo = Database::pdo();
        $now = time();

        try {
            $pdo->exec('BEGIN IMMEDIATE');

            $st = $pdo->prepare('SELECT * FROM cards WHERE code = ?');
            $st->execute([$code]);
            $card = $st->fetch();

            if (!$card) {
                $pdo->exec('ROLLBACK');
                self::log('redeem_fail', $pin, $code, $ip, $ua, 'not_found');
                return ['ok' => false, 'error' => 'card_not_found'];
            }
            if ((int) $card['status'] === 2) {
                $pdo->exec('ROLLBACK');
                self::log('redeem_fail', $pin, $code, $ip, $ua, 'revoked');
                return ['ok' => false, 'error' => 'card_revoked'];
            }

            $bound = trim((string) ($card['bound_pin'] ?? ''));

            /* 从未绑定：原子绑定，防两台设备同时抢 */
            if ((int) $card['status'] === 0 || $bound === '') {
                $cardUntil = $now + max(60, (int) $card['duration_sec']);
                $upd = $pdo->prepare(
                    'UPDATE cards SET status = 1, redeemed_at = ?, expire_at = ?, bound_pin = ?, bound_ip = ?
                     WHERE id = ? AND (bound_pin IS NULL OR bound_pin = \'\')'
                );
                $upd->execute([$now, $cardUntil, $pin, $ip, $card['id']]);
                if ($upd->rowCount() !== 1) {
                    $pdo->exec('ROLLBACK');
                    self::log('redeem_fail', $pin, $code, $ip, $ua, 'race');
                    return ['ok' => false, 'error' => 'card_used'];
                }
                $st->execute([$code]);
                $card = $st->fetch();
                $bound = $pin;
            }

            if ($bound !== '' && $bound !== $pin) {
                $pdo->exec('ROLLBACK');
                self::log('redeem_fail', $pin, $code, $ip, $ua, 'bound_to_other');
                return ['ok' => false, 'error' => 'card_bound'];
            }

            $expire = (int) ($card['expire_at'] ?? 0);
            if ($expire <= 0) {
                $expire = $now + max(60, (int) $card['duration_sec']);
            }
            if ($expire <= $now) {
                $pdo->exec('ROLLBACK');
                self::log('redeem_fail', $pin, $code, $ip, $ua, 'expired');
                return ['ok' => false, 'error' => 'card_expired'];
            }

            $pdo->exec('COMMIT');

            return ['ok' => true, 'card' => [
                'id'        => (int) $card['id'],
                'code'      => $code,
                'expire_at' => $expire,
                'duration'  => (int) $card['duration_sec'],
            ]];
        } catch (Throwable $e) {
            try { $pdo->exec('ROLLBACK'); } catch (Throwable $ignored) {}
            Log::file('app', 'session bind error: ' . $e->getMessage());
            return ['ok' => false, 'error' => 'server_error'];
        }
    }

    /**
     * 下发/刷新授权窗口，并写回配对码记录
     *
     * @param array{id:int,code:string,expire_at:int} $card
     */
    public static function grant(string $pin, array $card, string $ip, string $ua, bool $countUse): array
    {
        $pdo = Database::pdo();
        $now = time();
        $win = self::window();
        $until = min((int) $card['expire_at'], $now + $win);

        try {
            $st = $pdo->prepare('SELECT pin FROM pins WHERE pin = ?');
            $st->execute([$pin]);
            if ($st->fetchColumn()) {
                $pdo->prepare(
                    'UPDATE pins SET authorized_until = ?, card_id = ?, last_seen = ?, ip = ?,
                            redeem_count = redeem_count + ?
                     WHERE pin = ?'
                )->execute([$until, $card['id'], $now, $ip, $countUse ? 1 : 0, $pin]);
            } else {
                $pdo->prepare(
                    'INSERT INTO pins(pin, first_seen, last_seen, ip, ua, card_id, authorized_until, redeem_count)
                     VALUES(?,?,?,?,?,?,?,?)'
                )->execute([$pin, $now, $now, $ip, $ua, $card['id'], $until, $countUse ? 1 : 0]);
            }

            /* 只在真正兑换时留痕，续期不再刷记录 */
            if ($countUse) {
                $pdo->prepare('INSERT INTO card_uses(card_id, pin, ip, ts) VALUES(?,?,?,?)')
                    ->execute([$card['id'], $pin, $ip, $now]);
            }
        } catch (Throwable $e) {
            Log::file('app', 'session grant error: ' . $e->getMessage());
            return ['ok' => false, 'error' => 'server_error'];
        }

        return self::payload($card, $until, $now);
    }

    /** 兑换（首次激活 / 换卡续时） */
    public static function redeem(string $pin, string $rawCode, string $ip, string $ua): array
    {
        $b = self::bind($pin, $rawCode, $ip, $ua);
        if (!$b['ok']) {
            return $b;
        }
        $r = self::grant($pin, $b['card'], $ip, $ua, true);
        if ($r['ok']) {
            self::log('redeem_ok', $pin, $b['card']['code'], $ip, $ua,
                      'until=' . $r['authorized_until'] . ' card=' . $r['card_expire_at']);
        }
        return $r;
    }

    /** 续期：不新增兑换记录，只把窗口往后推 */
    public static function renew(string $pin, string $rawCode, string $ip, string $ua): array
    {
        if ($rawCode === '') {
            $row = self::currentCard($pin);
            if (!$row) {
                return ['ok' => false, 'error' => 'card_not_found'];
            }
            $rawCode = (string) $row;
        }
        $b = self::bind($pin, $rawCode, $ip, $ua);
        if (!$b['ok']) {
            return $b;
        }
        return self::grant($pin, $b['card'], $ip, $ua, false);
    }

    /** 只读状态：不改任何计数，供 UI 拉真实状态 */
    public static function state(string $pin): array
    {
        $now = time();
        $pdo = Database::pdo();
        $st = $pdo->prepare(
            'SELECT p.pin, p.authorized_until, p.card_id, c.code, c.status, c.expire_at
             FROM pins p LEFT JOIN cards c ON c.id = p.card_id WHERE p.pin = ?'
        );
        $st->execute([$pin]);
        $row = $st->fetch();
        if (!$row) {
            return [
                'ok' => true, 'pin' => $pin, 'authorized' => false,
                'authorized_until' => 0, 'expires_in' => 0,
                'card_expire_at' => 0, 'card_seconds_left' => 0, 'card_status' => 0,
                'window' => self::window(), 'grace' => self::grace(), 'server_time' => $now,
            ];
        }

        $until = (int) $row['authorized_until'];
        $cardExpire = (int) ($row['expire_at'] ?? 0);
        return [
            'ok'                 => true,
            'pin'                => $pin,
            'authorized'         => $until > $now,
            'authorized_until'   => $until,
            'expires_in'         => max(0, $until - $now),
            'card_expire_at'     => $cardExpire,
            'card_seconds_left'  => max(0, $cardExpire - $now),
            'card_status'        => (int) ($row['status'] ?? 0),
            'card'               => $row['code'] ? substr((string) $row['code'], 0, 4) . '****' : null,
            'window'             => self::window(),
            'grace'              => self::grace(),
            'server_time'        => $now,
        ];
    }

    /** 该配对码当前绑定的卡密编号（续期时没带卡密就用它） */
    private static function currentCard(string $pin): ?string
    {
        $st = Database::pdo()->prepare('SELECT c.code FROM pins p JOIN cards c ON c.id = p.card_id WHERE p.pin = ?');
        $st->execute([$pin]);
        $code = $st->fetchColumn();
        return $code ? (string) $code : null;
    }

    private static function payload(array $card, int $until, int $now): array
    {
        return [
            'ok'                   => true,
            'expires_in'           => max(0, $until - $now),
            /* expire_at 保持旧语义（本次窗口结束），老客户端不受影响 */
            'expire_at'            => $until,
            'authorized_until'     => $until,
            'card_expire_at'       => (int) $card['expire_at'],
            'card_seconds_left'    => max(0, (int) $card['expire_at'] - $now),
            'window'               => self::window(),
            'grace'                => self::grace(),
            'server_time'          => $now,
        ];
    }

    private static function log(string $kind, ?string $pin, ?string $code, string $ip, string $ua, string $detail): void
    {
        CardService::event($kind, $pin, $code, $ip, $ua, $detail);
    }
}
