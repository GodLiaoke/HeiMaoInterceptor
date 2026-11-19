<?php
declare(strict_types=1);

/** 卡密：生成 / 兑换 / 作废 / 查询 */
final class CardService
{
    private const ALPHABET = 'ACDEFGHJKLMNPQRTUVWXY34679';
    private const CHARSETS = [
        'std'   => 'ACDEFGHJKLMNPQRTUVWXY34679',       /* 无歧义：去形近字 */
        'digit' => '0123456789',                        /* 纯数字 */
        'alpha' => 'ACDEFGHJKLMNPQRTUVWXY',             /* 纯字母 */
        'full'  => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',  /* 全量 */
    ];
    private const GROUP    = 4;
    private const GROUPS   = 4;

    /* 授权下发窗口（秒）：卡密激活 / 续期后，配对码只在这么多秒内拿得到授权，
       够客户端（5 秒一轮）取到授权数据即可。可用 storage/config.php 的
       auth_window_sec 覆盖。 */
    private const AUTH_WINDOW_SEC = 60;

    public static function generateCode(string $charset = 'std'): string
    {
        $a = self::CHARSETS[$charset] ?? self::ALPHABET;
        $max = strlen($a) - 1;
        $parts = [];
        for ($g = 0; $g < self::GROUPS; $g++) {
            $s = '';
            for ($i = 0; $i < self::GROUP; $i++) {
                $s .= $a[random_int(0, $max)];
            }
            $parts[] = $s;
        }
        return implode('-', $parts);
    }

    public static function normalise(string $code): string
    {
        $code = strtoupper(trim($code));
        $code = preg_replace('/[^A-Z0-9]/', '', $code) ?? '';
        if (strlen($code) === 16) {
            return implode('-', str_split($code, 4));
        }
        return $code;
    }

    /** @return array{created:int,codes:string[]} */
    public static function createBatch(int $count, int $durationSec, string $batch, string $note, string $admin, string $ip, string $charset = 'std', string $tier = 'pro'): array
    {
        $tier = TierService::normalise($tier);
        $count = max(1, min(1000, $count));
        $durationSec = max(60, min(86400 * 30, $durationSec));
        $pdo = Database::pdo();
        $pdo->beginTransaction();
        $codes = [];
        try {
            $ins = $pdo->prepare('INSERT INTO cards(code, batch, duration_sec, note, tier, created_at) VALUES(?,?,?,?,?,?)');
            $now = time();
            for ($i = 0; $i < $count; $i++) {
                for ($try = 0; $try < 8; $try++) {
                    $code = self::generateCode($charset);
                    try {
                        $ins->execute([$code, $batch, $durationSec, $note, $tier, $now]);
                        $codes[] = $code;
                        break;
                    } catch (PDOException $e) {
                        if (!str_contains($e->getMessage(), 'UNIQUE')) {
                            throw $e;
                        }
                    }
                }
            }
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([$now, $admin, 'card.generate', $batch, $ip,
                           json_encode(['count' => count($codes), 'duration' => $durationSec,
                                        'charset' => $charset, 'batch' => $batch,
                                        'tier' => $tier], 320)]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        return ['created' => count($codes), 'codes' => $codes, 'tier' => $tier];
    }

    /**
     * 兑换：原子绑定 pin，给 duration 秒授权（可叠加，从当前有效期往后加）
     * @return array{ok:bool,error?:string,expires_in?:int,expire_at?:int}
     */
    public static function redeem(string $pin, string $rawCode, string $ip, string $ua, string $dev = ''): array
    {
        /* 兑换统一走 SessionService：绑定规则、窗口、错误码只有一份实现 */
        return SessionService::redeem($pin, $rawCode, $ip, $ua, $dev);
    }

    public static function event(string $kind, ?string $pin, ?string $code, string $ip, string $ua, string $detail = ''): void
    {
        $pdo = Database::pdo();
        $now = time();
        $detail = substr($detail, 0, 255);

        /* 同一配对码 + 同一 IP + 同一原因，60 秒内只留一条（刷新时间戳），
           避免客户端连不上/重试时把日志刷成几百条一样的记录 */
        try {
            $st = $pdo->prepare(
                "SELECT id FROM events
                 WHERE kind = ? AND COALESCE(pin, '') = ? AND ip = ? AND COALESCE(detail, '') = ? AND ts > ?
                 ORDER BY id DESC LIMIT 1"
            );
            $st->execute([$kind, (string) $pin, $ip, $detail, $now - 60]);
            $hit = $st->fetchColumn();
            if ($hit) {
                $pdo->prepare('UPDATE events SET ts = ? WHERE id = ?')->execute([$now, (int) $hit]);
                return;
            }
        } catch (Throwable $e) {
            /* 去重查询失败不影响主流程，照常插入 */
        }

        $pdo->prepare('INSERT INTO events(ts, kind, pin, code, ip, ua, detail) VALUES(?,?,?,?,?,?,?)')
            ->execute([$now, $kind, $pin, $code, $ip, $ua, $detail]);
    }

    public static function listPage(int $page, int $per, string $q = '', int $status = -1, string $batch = ''): array
    {
        $pdo = Database::pdo();
        $where = ['1=1'];
        $args = [];
        if ($status >= 0) { $where[] = 'status = ?'; $args[] = $status; }
        if ($batch !== '') { $where[] = 'batch = ?'; $args[] = $batch; }
        if ($q !== '') {
            $where[] = '(code LIKE ? OR batch LIKE ? OR bound_pin LIKE ? OR bound_ip LIKE ? OR note LIKE ?)';
            $like = '%' . $q . '%';
            array_push($args, $like, $like, $like, $like, $like);
        }
        $w = implode(' AND ', $where);
        $st = $pdo->prepare("SELECT COUNT(*) FROM cards WHERE $w");
        $st->execute($args);
        $total = (int) $st->fetchColumn();
        $off = max(0, ($page - 1) * $per);
        $st = $pdo->prepare("SELECT id, code, batch, duration_sec, status, bound_pin, bound_ip, bound_dev,
                                    redeemed_at, expire_at, note, tier, ban_reason, banned_at, created_at
                             FROM cards WHERE $w ORDER BY id DESC LIMIT ? OFFSET ?");
        foreach ($args as $i => $a) { $st->bindValue($i + 1, $a); }
        $st->bindValue(count($args) + 1, $per, PDO::PARAM_INT);
        $st->bindValue(count($args) + 2, $off, PDO::PARAM_INT);
        $st->execute();
        return ['total' => $total, 'rows' => $st->fetchAll()];
    }

    /**
     * 单张卡密详情：卡本身 + 绑定的配对码 / 设备 + 最近事件 + 历史设备
     * 后台「详情」面板一次拿全，不再靠列表里的那几列猜。
     */
    public static function detail(int $id): array
    {
        $pdo = Database::pdo();
        $st = $pdo->prepare('SELECT id, code, batch, duration_sec, status, bound_pin, bound_ip, bound_dev,
                                    redeemed_at, expire_at, note, tier, ban_reason, banned_at, created_at
                             FROM cards WHERE id = ?');
        $st->execute([$id]);
        $card = $st->fetch();
        if (!$card) {
            return [];
        }
        $now = time();
        $card['tier']       = TierService::normalise((string) ($card['tier'] ?? TierService::PRO));
        $card['tier_label'] = TierService::label($card['tier']);
        $card['seconds_left'] = (int) $card['expire_at'] > 0 ? max(0, (int) $card['expire_at'] - $now) : 0;
        $card['expired']      = (int) $card['expire_at'] > 0 && (int) $card['expire_at'] <= $now;

        $pin = (string) ($card['bound_pin'] ?? '');
        $card['pin_info'] = null;
        if ($pin !== '') {
            $ps = $pdo->prepare('SELECT pin, first_seen, last_seen, ip, ua, card_id, authorized_until,
                                        redeem_count, last_beat, app_ver, kick_at, kick_reason
                                 FROM pins WHERE pin = ?');
            $ps->execute([$pin]);
            $p = $ps->fetch();
            if ($p) {
                $p['online']     = (int) $p['last_beat'] > $now - 150;
                $p['kicked']     = (int) $p['kick_at'] > 0;
                $p['authorized'] = (int) $p['authorized_until'] > $now;
                $card['pin_info'] = $p;
            }
        }

        $es = $pdo->prepare('SELECT ts, kind, pin, ip, detail FROM events
                             WHERE code = ?' . ($pin !== '' ? ' OR pin = ?' : '') . '
                             ORDER BY id DESC LIMIT 15');
        $es->execute($pin !== '' ? [$card['code'], $pin] : [$card['code']]);
        $card['events'] = $es->fetchAll();

        /* 这张卡历史上用过的设备：判断有没有被共享 / 换机，比单看 bound_pin 直观 */
        $hs = $pdo->prepare('SELECT pin, COUNT(*) c, MAX(ts) last_ts FROM events
                             WHERE code = ? AND pin IS NOT NULL AND pin <> ""
                             GROUP BY pin ORDER BY last_ts DESC LIMIT 10');
        $hs->execute([$card['code']]);
        $card['devices'] = $hs->fetchAll();

        return $card;
    }

    /** 改卡密等级：free / beta / pro / max，下次校验起按新等级下发规则 */
    public static function setTier(int $id, string $tier, string $admin, string $ip): array
    {
        if (!TierService::valid($tier)) {
            return ['ok' => false, 'error' => 'bad_tier'];
        }
        $tier = TierService::normalise($tier);
        $pdo = Database::pdo();
        $card = $pdo->query('SELECT id, code, tier FROM cards WHERE id = ' . (int) $id)->fetch();
        if (!$card) {
            return ['ok' => false, 'error' => 'not_found'];
        }
        $old = TierService::normalise((string) $card['tier']);
        $pdo->prepare('UPDATE cards SET tier = ? WHERE id = ?')->execute([$tier, $id]);
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'card.tier', (string) $id, $ip,
                       'tier ' . $old . ' -> ' . $tier . ' code=' . $card['code']]);
        return ['ok' => true, 'tier' => $tier, 'tier_label' => TierService::label($tier), 'old' => $old];
    }

    public static function setStatus(int $id, int $status, string $admin, string $ip, string $reason = ''): bool
    {
        $pdo = Database::pdo();
        $card = $pdo->query('SELECT id, expire_at FROM cards WHERE id = ' . (int) $id)->fetch();
        if (!$card) {
            return false;
        }
        $reason = mb_substr(trim($reason), 0, 120);
        /* 解封：有到期时间的回到"已激活"，从未激活的回到"未激活" */
        if ($status === 0 || $status === 1) {
            $status = ((int) $card['expire_at'] > 0) ? 1 : 0;
        }
        if ($status === 2) {
            $st = $pdo->prepare('UPDATE cards SET status = ?, ban_reason = ?, banned_at = ? WHERE id = ?');
            $st->execute([$status, $reason !== '' ? $reason : '管理员封禁', time(), $id]);
        } else {
            $st = $pdo->prepare("UPDATE cards SET status = ?, ban_reason = '', banned_at = 0 WHERE id = ?");
            $st->execute([$status, $id]);
        }
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, $status === 2 ? 'card.ban' : 'card.unban', (string) $id, $ip,
                       'status=' . $status . ($reason !== '' ? ' reason=' . $reason : '')]);
        if ($status === 2) {
            /* 作废：绑定这个卡密的所有配对码会话立刻封掉，
               客户端下一次校验就会收到 card_revoked，界面同步变未授权 */
            AuthGate::sealByCard((int) $id);
        } elseif ($status === 1) {
            /* 解封：授权窗口同样只给 window 秒，不再整段下发到卡密到期 */
            /* 解封：按 pins.card_id 直接恢复，比走 card_uses 子查询更可靠 */
            $grant = min((int) $card['expire_at'], time() + self::authWindow());
            $pdo->prepare('UPDATE pins SET authorized_until = ? WHERE card_id = ?')
                ->execute([$grant, $id]);
        }
        return true;
    }

    /** 延期：天数可正（延长）也可负（缩短） */
    public static function extend(int $id, int $days, string $admin, string $ip): array
    {
        $pdo = Database::pdo();
        $card = $pdo->query('SELECT id, status, duration_sec, expire_at FROM cards WHERE id = ' . (int) $id)->fetch();
        if (!$card) {
            return ['ok' => false, 'error' => 'not_found'];
        }
        $delta = $days * 86400;
        $pdo->beginTransaction();
        try {
            if ((int) $card['status'] === 0) {
                $newDur = max(60, (int) $card['duration_sec'] + $delta);
                $pdo->prepare('UPDATE cards SET duration_sec = ? WHERE id = ?')->execute([$newDur, $id]);
                $newExpire = 0;
            } else {
                $newExpire = max(time(), (int) $card['expire_at'] + $delta);
                $pdo->prepare('UPDATE cards SET expire_at = ?, duration_sec = ? WHERE id = ?')
                    ->execute([$newExpire, max(60, $newExpire - time()), $id]);
                $grant = min($newExpire, time() + self::authWindow());
                $pdo->prepare('UPDATE pins SET authorized_until = ? WHERE card_id = ?')
                    ->execute([$grant, $id]);
            }
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'card.extend', (string) $id, $ip,
                           'days=' . $days . ' expire=' . $newExpire]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        return ['ok' => true, 'expire_at' => $newExpire];
    }

    /** 解绑：保留卡密剩余时长，只放开设备绑定，换机能接着用 */
    public static function unbind(int $id, string $admin, string $ip): bool
    {
        $pdo = Database::pdo();
        $card = $pdo->query('SELECT id, bound_pin FROM cards WHERE id = ' . (int) $id)->fetch();
        if (!$card) {
            return false;
        }
        $oldPin = (string) ($card['bound_pin'] ?? '');
        $pdo->beginTransaction();
        try {
            $pdo->prepare('UPDATE cards SET bound_pin = NULL, bound_ip = NULL WHERE id = ?')->execute([$id]);
            if ($oldPin !== '') {
                $pdo->prepare('UPDATE pins SET authorized_until = 0 WHERE pin = ?')->execute([$oldPin]);
            }
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'card.unbind', (string) $id, $ip, 'was=' . $oldPin]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        return true;
    }

    public static function remove(int $id, string $admin, string $ip): bool
    {
        $pdo = Database::pdo();
        $card = $pdo->query('SELECT id, code FROM cards WHERE id = ' . (int) $id)->fetch();
        if (!$card) {
            return false;
        }
        $pdo->beginTransaction();
        try {
            AuthGate::sealByCard((int) $id);
            $pdo->prepare('DELETE FROM card_uses WHERE card_id = ?')->execute([$id]);
            $pdo->prepare('DELETE FROM cards WHERE id = ?')->execute([$id]);
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'card.delete', (string) $id, $ip, (string) $card['code']]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        return true;
    }

    /** 授权窗口秒数（统一由 SessionService 提供，默认 600） */
    private static function authWindow(): int
    {
        return SessionService::window();
    }

    public static function stats(): array
    {
        $p = Database::pdo();
        $one = fn(string $sql) => (int) $p->query($sql)->fetchColumn();
        $now = time();
        return [
            'cards_total'   => $one('SELECT COUNT(*) FROM cards'),
            'cards_unused'  => $one('SELECT COUNT(*) FROM cards WHERE status = 0'),
            'cards_used'    => $one('SELECT COUNT(*) FROM cards WHERE status = 1'),
            'cards_revoked' => $one('SELECT COUNT(*) FROM cards WHERE status = 2'),
            'pins_total'    => $one('SELECT COUNT(*) FROM pins'),
            'pins_online'   => (int) $p->query('SELECT COUNT(*) FROM pins WHERE authorized_until > ' . $now)->fetchColumn(),
            'pins_beat'     => (int) $p->query('SELECT COUNT(*) FROM pins WHERE last_beat > ' . ($now - 150))->fetchColumn(),
            'pins_kicked'   => (int) $p->query('SELECT COUNT(*) FROM pins WHERE kick_at > 0')->fetchColumn(),
            'redeem_24h'    => $one('SELECT COUNT(*) FROM events WHERE kind = "redeem_ok" AND ts > ' . ($now - 86400)),
            'fail_24h'      => $one('SELECT COUNT(*) FROM events WHERE kind = "redeem_fail" AND ts > ' . ($now - 86400)),
        ];
    }
}
