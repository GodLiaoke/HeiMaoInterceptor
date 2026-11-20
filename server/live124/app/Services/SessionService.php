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
    public static function bind(string $pin, string $rawCode, string $ip, string $ua, string $dev = ''): array
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
                return ['ok' => false, 'error' => 'card_revoked',
                        'ban_reason' => (string) ($card['ban_reason'] ?? '')];
            }

            $bound = trim((string) ($card['bound_pin'] ?? ''));

            /* 从未绑定：原子绑定，防两台设备同时抢 */
            if ((int) $card['status'] === 0 || $bound === '') {
                $cardUntil = $now + max(60, (int) $card['duration_sec']);
                $upd = $pdo->prepare(
                    'UPDATE cards SET status = 1, redeemed_at = ?, expire_at = ?, bound_pin = ?, bound_ip = ?, bound_dev = ?
                     WHERE id = ? AND (bound_pin IS NULL OR bound_pin = \'\')'
                );
                $upd->execute([$now, $cardUntil, $pin, $ip, $dev, $card['id']]);
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
                $cardDev = trim((string) ($card['bound_dev'] ?? ''));

                /* 同一台设备换了设备码（老版本随机码、卸载重装）：
                   设备指纹对得上就把绑定迁到新设备码，卡密与到期时间都不动。
                   指纹对不上才判 card_bound，杜绝一张卡两台机器同时用。 */
                if ($dev !== '' && $cardDev !== '' && hash_equals($cardDev, $dev)) {
                    $oldPin = $bound;
                    $pdo->prepare('UPDATE cards SET bound_pin = ?, bound_ip = ? WHERE id = ?')
                        ->execute([$pin, $ip, $card['id']]);
                    $pdo->prepare('UPDATE pins SET card_id = NULL, authorized_until = 0 WHERE pin = ?')
                        ->execute([$oldPin]);
                    self::log('rebind_same_device', $pin, $code, $ip, $ua,
                              'from=' . $oldPin . ' dev=' . substr($dev, 0, 8));
                    $bound = $pin;
                } elseif ($cardDev === '' && self::oldPinIdle($bound, 900)) {
                    /* 升级前绑的卡没记设备指纹：旧设备码已经 15 分钟没联网，
                       说明就是这台机器重装后换了码，让它认领一次，之后严格按指纹。
                       一张卡只会有这一次，认领完就记上 bound_dev。 */
                    $oldPin = $bound;
                    $pdo->prepare('UPDATE cards SET bound_pin = ?, bound_ip = ?, bound_dev = ? WHERE id = ?')
                        ->execute([$pin, $ip, $dev, $card['id']]);
                    $pdo->prepare('UPDATE pins SET card_id = NULL, authorized_until = 0 WHERE pin = ?')
                        ->execute([$oldPin]);
                    self::log('rebind_legacy', $pin, $code, $ip, $ua,
                              'from=' . $oldPin . ' dev=' . substr($dev, 0, 8));
                    $bound = $pin;
                } else {
                    $pdo->exec('ROLLBACK');
                    self::log('redeem_fail', $pin, $code, $ip, $ua, 'bound_to_other');
                    return ['ok' => false, 'error' => 'card_bound'];
                }
            }

            $expire = (int) ($card['expire_at'] ?? 0);
            if ($expire <= 0) {
                $expire = $now + max(60, (int) $card['duration_sec']);
            }
            if ($expire <= $now) {
                /* 1.2.3：已经兑换过又过期的卡，用户在客户端再激活一次就直接清掉，
                   不留一堆永远用不上的死卡。未兑换的过期（理论上不会有）只回错误。 */
                $purged = false;
                $redeemed = ((int) ($card['status'] ?? 0) === 1)
                    && ((int) ($card['redeemed_at'] ?? 0) > 0);
                if ($redeemed) {
                    try {
                        $pdo->prepare('UPDATE pins SET card_id = NULL, authorized_until = 0 WHERE card_id = ?')
                            ->execute([$card['id']]);
                        $pdo->prepare('DELETE FROM card_uses WHERE card_id = ?')->execute([$card['id']]);
                        $pdo->prepare('DELETE FROM cards WHERE id = ?')->execute([$card['id']]);
                        $pdo->exec('COMMIT');
                        $purged = true;
                    } catch (Throwable $e) {
                        try { $pdo->exec('ROLLBACK'); } catch (Throwable $ignored) {}
                        Log::file('app', 'expired card purge error: ' . $e->getMessage());
                    }
                } else {
                    $pdo->exec('ROLLBACK');
                }
                self::log('redeem_fail', $pin, $code, $ip, $ua, $purged ? 'expired_purged' : 'expired');
                return ['ok' => false, 'error' => 'card_expired', 'purged' => $purged];
            }

            $pdo->exec('COMMIT');

            return ['ok' => true, 'card' => [
                'id'        => (int) $card['id'],
                'code'      => $code,
                'expire_at' => $expire,
                'duration'  => (int) $card['duration_sec'],
                'tier'      => TierService::normalise((string) ($card['tier'] ?? TierService::PRO)),
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
    public static function redeem(string $pin, string $rawCode, string $ip, string $ua, string $dev = ''): array
    {
        $kick = self::kickInfo($pin);
        if ($kick['kicked']) {
            return ['ok' => false, 'error' => 'kicked', 'kick_reason' => $kick['reason']];
        }
        $b = self::bind($pin, $rawCode, $ip, $ua, $dev);
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
    public static function renew(string $pin, string $rawCode, string $ip, string $ua, string $dev = '', string $appVer = ''): array
    {
        /* 被管理员强制下线的设备，续期一律不通过（否则它会一直拿回窗口） */
        $kick = self::kickInfo($pin);
        if ($kick['kicked']) {
            return ['ok' => false, 'error' => 'kicked', 'kick_reason' => $kick['reason']];
        }

        /* 在线统计：客户端每 60 秒续期一次，这里顺手记一下心跳和版本。
           老客户端不带 ver，也照样记心跳（后台能看到在线，只是版本号空着）。 */
        try {
            if ($appVer !== '') {
                Database::pdo()
                    ->prepare('UPDATE pins SET last_beat = ?, app_ver = ? WHERE pin = ?')
                    ->execute([time(), substr(preg_replace('/[^0-9A-Za-z.() ]/', '', $appVer) ?? '', 0, 32), $pin]);
            } else {
                Database::pdo()
                    ->prepare('UPDATE pins SET last_beat = ? WHERE pin = ?')
                    ->execute([time(), $pin]);
            }
        } catch (Throwable $e) {
            Log::file('app', 'renew beat error: ' . $e->getMessage());
        }

        /* 快路径：卡密已绑定、状态正常、窗口还剩一半以上 -> 直接回包，一个字都不写库。
           续期原来每次都开 BEGIN IMMEDIATE，多设备同时续期会把 SQLite 写锁排满，
           请求就一个个排队等锁，表现成「整个界面卡住」。 */
        $now = time();
        $win = self::window();
        $peek = self::peek($pin);
        if ($peek !== null
            && ($rawCode === '' || CardService::normalise($rawCode) === (string) $peek['code'])
            && (int) $peek['status'] !== 2
            && (int) $peek['expire_at'] > $now
            && (int) $peek['authorized_until'] > $now + intdiv($win, 2)) {
            return self::payload([
                'id'        => (int) $peek['id'],
                'code'      => (string) $peek['code'],
                'expire_at' => (int) $peek['expire_at'],
                'duration'  => (int) $peek['duration_sec'],
                'tier'      => TierService::normalise((string) ($peek['tier'] ?? TierService::PRO)),
            ], (int) $peek['authorized_until'], $now);
        }

        if ($rawCode === '') {
            $row = self::currentCard($pin);
            if (!$row) {
                return ['ok' => false, 'error' => 'card_not_found'];
            }
            $rawCode = (string) $row;
        }
        $b = self::bind($pin, $rawCode, $ip, $ua, $dev);
        if (!$b['ok']) {
            return $b;
        }
        return self::grant($pin, $b['card'], $ip, $ua, false);
    }

    /**
     * 设备指纹找回：客户端换了设备码、手上又没带卡密时，
     * 按设备指纹把之前绑过的卡密认回来（重装后不用重新输卡密）。
     */
    public static function adoptByDev(string $pin, string $dev, string $ip, string $ua): ?array
    {
        if ($dev === '' || strlen($dev) < 16) {
            return null;
        }
        $pdo = Database::pdo();
        $st = $pdo->prepare(
            'SELECT * FROM cards WHERE bound_dev = ? AND status = 1 ORDER BY expire_at DESC LIMIT 1');
        $st->execute([$dev]);
        $card = $st->fetch();
        if (!$card || (int) $card['expire_at'] <= time()) {
            return null;
        }

        $old = trim((string) ($card['bound_pin'] ?? ''));

        /* 1.2.4 安全修复：设备指纹认领（重装后免输卡密）以前没有任何前置条件，
           只要知道一台设备的指纹就能把卡密抢到自己的配对码上，原设备当场被踢。
           现在要求「原设备确实已经离线」才允许认领：
             · 原设备在线（150 秒内还有活动）→ 拒绝，防止在线抢占
             · 原设备已离线 / 从未绑定 → 放行，重装用户的正常路径不受影响 */
        if ($old !== '' && $old !== $pin && !self::oldPinIdle($old, 150)) {
            self::log('adopt_reject', $pin, (string) $card['code'], $ip, $ua, 'old_pin_active=' . $old);
            return null;
        }

        if ($old !== $pin) {
            try {
                $pdo->prepare('UPDATE cards SET bound_pin = ?, bound_ip = ? WHERE id = ?')
                    ->execute([$pin, $ip, $card['id']]);
                if ($old !== '') {
                    $pdo->prepare('UPDATE pins SET card_id = NULL, authorized_until = 0 WHERE pin = ?')
                        ->execute([$old]);
                }
                self::log('adopt_by_dev', $pin, (string) $card['code'], $ip, $ua, 'from=' . $old);
            } catch (Throwable $e) {
                Log::file('app', 'adopt by dev error: ' . $e->getMessage());
                return null;
            }
        }

        return self::grant($pin, [
            'id'        => (int) $card['id'],
            'code'      => (string) $card['code'],
            'expire_at' => (int) $card['expire_at'],
            'duration'  => (int) $card['duration_sec'],
        ], $ip, $ua, false);
    }

    /** 只读状态：不改任何计数，供 UI 拉真实状态 */
    public static function state(string $pin): array
    {
        $g = AuthGate::evaluate($pin);
        return [
            'ok'                 => true,
            'pin'                => $pin,
            'authorized'         => $g['authorized'],
            'reason'             => $g['reason'],
            'authorized_until'   => $g['authorized_until'],
            'expires_in'         => $g['expires_in'],
            'card_expire_at'     => $g['card_expire_at'],
            'card_seconds_left'  => $g['card_seconds_left'],
            'card_status'        => $g['card_status'],
            'card'               => $g['card'],
            'window'             => self::window(),
            'grace'              => self::grace(),
            'tier'               => $g['tier'] ?? TierService::PRO,
            'tier_label'         => $g['tier_label'] ?? TierService::PRO,
            'ban_reason'         => $g['ban_reason'] ?? '',
            'kick'               => $g['kick'] ?? false,
            'kick_reason'        => $g['kick_reason'] ?? '',
            'server_time'        => time(),
        ];
    }

    /**
     * 心跳：记录在线状态与客户端版本，并回传「是否被强制下线」
     * 后台「在线」列表就是按 last_beat 排序的，150 秒内有心跳算在线。
     */
    public static function beat(string $pin, string $appVer = '', string $ip = '', string $ua = ''): array
    {
        $pdo = Database::pdo();
        $now = time();
        $appVer = substr(preg_replace('/[^0-9A-Za-z.() ]/', '', $appVer) ?? '', 0, 32);
        try {
            $pdo->prepare('UPDATE pins SET last_beat = ?, app_ver = ? WHERE pin = ?')
                ->execute([$now, $appVer, $pin]);
        } catch (Throwable $e) {
            Log::file('app', 'beat error: ' . $e->getMessage());
        }
        $kick = self::kickInfo($pin);
        $g = AuthGate::evaluate($pin, false);
        return [
            'ok'          => true,
            'beat'        => $now,
            'online'      => true,
            'kicked'      => $kick['kicked'],
            'kick_reason' => $kick['reason'],
            'authorized'  => $g['authorized'],
            'reason'      => $g['reason'],
            'card_seconds_left' => $g['card_seconds_left'],
            'tier'        => $g['tier'] ?? TierService::PRO,
            'tier_label'  => $g['tier_label'] ?? TierService::PRO,
            'ban_reason'  => $g['ban_reason'] ?? '',
        ];
    }

    /** 这个配对码有没有被后台踢下线 */
    public static function kickInfo(string $pin): array
    {
        try {
            $st = Database::pdo()->prepare('SELECT kick_at, kick_reason FROM pins WHERE pin = ?');
            $st->execute([$pin]);
            $row = $st->fetch();
            if (!$row) {
                return ['kicked' => false, 'reason' => ''];
            }
            return [
                'kicked' => (int) ($row['kick_at'] ?? 0) > 0,
                'reason' => (string) ($row['kick_reason'] ?? ''),
            ];
        } catch (Throwable $e) {
            return ['kicked' => false, 'reason' => ''];
        }
    }

    /** 后台强制下线 / 解除 */
    public static function kick(string $pin, string $reason, string $admin, string $ip): array
    {
        $reason = mb_substr(trim($reason), 0, 120);
        if ($reason === '') {
            $reason = '管理员强制下线';
        }
        $pdo = Database::pdo();
        $pdo->prepare('UPDATE pins SET kick_at = ?, kick_reason = ?, authorized_until = 0 WHERE pin = ?')
            ->execute([time(), $reason, $pin]);
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'pin.kick', $pin, $ip, 'reason=' . $reason]);
        return ['ok' => true, 'pin' => $pin, 'kicked' => true, 'reason' => $reason];
    }

    public static function unkick(string $pin, string $admin, string $ip): array
    {
        $pdo = Database::pdo();
        $pdo->prepare("UPDATE pins SET kick_at = 0, kick_reason = '' WHERE pin = ?")->execute([$pin]);
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'pin.unkick', $pin, $ip, '']);
        return ['ok' => true, 'pin' => $pin, 'kicked' => false];
    }

    /** 后台在线列表：心跳在线的设备 + 绑定卡密 + 版本 */
    public static function online(int $withinSec = 300, int $limit = 200): array
    {
        $pdo = Database::pdo();
        $now = time();
        $st = $pdo->prepare(
            'SELECT p.pin, p.last_seen, p.last_beat, p.app_ver, p.ip, p.authorized_until,
                    p.kick_at, p.kick_reason,
                    c.code, c.tier, c.status AS card_status, c.expire_at, c.ban_reason
             FROM pins p LEFT JOIN cards c ON c.id = p.card_id
             WHERE p.last_beat > ?
             ORDER BY p.last_beat DESC LIMIT ?'
        );
        $st->bindValue(1, $now - $withinSec, PDO::PARAM_INT);
        $st->bindValue(2, $limit, PDO::PARAM_INT);
        $st->execute();
        $rows = $st->fetchAll();
        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'pin'          => (string) $r['pin'],
                'code'         => (string) ($r['code'] ?? ''),
                'tier'         => TierService::normalise((string) ($r['tier'] ?? TierService::PRO)),
                'tier_label'   => TierService::label((string) ($r['tier'] ?? TierService::PRO)),
                'app_ver'      => (string) ($r['app_ver'] ?? ''),
                'ip'           => (string) ($r['ip'] ?? ''),
                'last_beat'    => (int) ($r['last_beat'] ?? 0),
                'online_s'     => max(0, $now - (int) ($r['last_beat'] ?? 0)),
                'authorized'   => (int) ($r['authorized_until'] ?? 0) > $now,
                'card_status'  => (int) ($r['card_status'] ?? 0),
                'card_expire_at' => (int) ($r['expire_at'] ?? 0),
                'kicked'       => (int) ($r['kick_at'] ?? 0) > 0,
                'kick_reason'  => (string) ($r['kick_reason'] ?? ''),
            ];
        }
        return [
            'rows'  => $out,
            'total' => count($out),
            'online_window' => $withinSec,
        ];
    }

    /** 旧设备码是不是已经闲置够久（老数据认领用） */
    private static function oldPinIdle(string $pin, int $idleSec): bool
    {
        if ($pin === '') {
            return true;
        }
        try {
            $st = Database::pdo()->prepare('SELECT last_seen FROM pins WHERE pin = ?');
            $st->execute([$pin]);
            $last = $st->fetchColumn();
            if ($last === false || $last === null) {
                return true;
            }
            return (time() - (int) $last) >= $idleSec;
        } catch (Throwable $e) {
            return false;
        }
    }

    /** 只读查询：配对码 + 绑定卡密的当前状态（不加任何锁、不写库） */
    private static function peek(string $pin): ?array
    {
        $st = Database::pdo()->prepare(
            'SELECT c.id, c.code, c.status, c.expire_at, c.duration_sec, c.tier,
                    p.authorized_until
             FROM pins p JOIN cards c ON c.id = p.card_id
             WHERE p.pin = ?'
        );
        $st->execute([$pin]);
        $row = $st->fetch();
        return $row ?: null;
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
            'authorized'           => true,
            'reason'               => AuthGate::OK,
            'expires_in'           => max(0, $until - $now),
            /* expire_at 保持旧语义（本次窗口结束），老客户端不受影响 */
            'expire_at'            => $until,
            'authorized_until'     => $until,
            'card_expire_at'       => (int) $card['expire_at'],
            'card_seconds_left'    => max(0, (int) $card['expire_at'] - $now),
            'window'               => self::window(),
            'grace'                => self::grace(),
            'tier'                 => TierService::normalise((string) ($card['tier'] ?? TierService::PRO)),
            'tier_label'           => TierService::label((string) ($card['tier'] ?? TierService::PRO)),
            'server_time'          => $now,
        ];
    }

    private static function log(string $kind, ?string $pin, ?string $code, string $ip, string $ua, string $detail): void
    {
        CardService::event($kind, $pin, $code, $ip, $ua, $detail);
    }
}
