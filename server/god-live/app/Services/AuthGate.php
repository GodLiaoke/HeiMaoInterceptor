<?php
declare(strict_types=1);

/**
 * 授权闸门 —— 全系统唯一的「能不能用」判定入口
 *
 * 之前的问题：authorized 只看 pins.authorized_until（在线校验窗口），
 * 卡密被后台作废 / 自然到期之后，窗口还没过的那几分钟里，
 * 服务端仍然回 authorized = true，客户端界面就继续显示「已授权」。
 *
 * 现在的判定顺序（任何一项不通过就立刻判定不可用）：
 *   1. 配对码存在且绑定了卡密        -> 否则 no_card
 *   2. 卡密存在（没被删）            -> 否则 card_not_found
 *   3. 卡密状态不是「已作废」(2)      -> 否则 card_revoked
 *   4. 卡密本身的到期时间还没到       -> 否则 card_expired
 *   5. 在线校验窗口还没过            -> 否则 window_expired
 *   6. 以上全过                      -> ok
 *
 * 判定为 card_revoked / card_expired / card_not_found 时，
 * 顺手把 pins.authorized_until 清零，防止任何旧逻辑继续放行。
 */
final class AuthGate
{
    public const OK              = 'ok';
    public const NO_CARD         = 'no_card';
    public const CARD_NOT_FOUND  = 'card_not_found';
    public const CARD_REVOKED    = 'card_revoked';
    public const CARD_EXPIRED    = 'card_expired';
    public const WINDOW_EXPIRED  = 'window_expired';

    /** 这些原因属于「卡密层面彻底作废」，可以立刻封掉会话 */
    private const HARD_FAIL = [self::CARD_NOT_FOUND, self::CARD_REVOKED, self::CARD_EXPIRED];

    /**
     * @return array{
     *   authorized:bool, reason:string, pin:string,
     *   card_status:int, card_expire_at:int, card_seconds_left:int,
     *   authorized_until:int, expires_in:int, card:?string
     * }
     */
    public static function evaluate(string $pin, bool $writeBack = true): array
    {
        $now = time();
        $pdo = Database::pdo();

        $st = $pdo->prepare(
            'SELECT p.pin, p.authorized_until, p.card_id,
                    c.code, c.status AS card_status, c.expire_at AS card_expire_at
             FROM pins p
             LEFT JOIN cards c ON c.id = p.card_id
             WHERE p.pin = ?'
        );
        $st->execute([$pin]);
        $row = $st->fetch();

        $base = [
            'pin'               => $pin,
            'card_status'       => 0,
            'card_expire_at'    => 0,
            'card_seconds_left' => 0,
            'authorized_until'  => 0,
            'expires_in'        => 0,
            'card'              => null,
            'server_time'       => $now,
        ];

        if (!$row) {
            return ['authorized' => false, 'reason' => self::NO_CARD] + $base;
        }

        $until      = (int) ($row['authorized_until'] ?? 0);
        $cardId     = (int) ($row['card_id'] ?? 0);
        $cardCode   = (string) ($row['code'] ?? '');
        $cardStatus = (int) ($row['card_status'] ?? 0);
        $cardExpire = (int) ($row['card_expire_at'] ?? 0);

        $base['authorized_until']  = $until;
        $base['expires_in']        = max(0, $until - $now);
        $base['card_status']       = $cardStatus;
        $base['card_expire_at']    = $cardExpire;
        $base['card_seconds_left'] = max(0, $cardExpire - $now);
        $base['card']              = $cardCode !== ''
            ? substr($cardCode, 0, 4) . '****'
            : null;

        /* 1. 没绑卡密 */
        if ($cardId <= 0 || $cardCode === '') {
            self::sealOff($pin, $writeBack);
            return ['authorized' => false, 'reason' => self::NO_CARD] + $base;
        }

        /* 2. 卡密记录不存在（被删了） */
        if (!isset($row['card_status']) || $row['card_status'] === null) {
            self::sealOff($pin, $writeBack);
            return ['authorized' => false, 'reason' => self::CARD_NOT_FOUND] + $base;
        }

        /* 3. 已作废 */
        if ($cardStatus === 2) {
            self::sealOff($pin, $writeBack);
            return ['authorized' => false, 'reason' => self::CARD_REVOKED] + self::sealed($base);
        }

        /* 4. 卡密本身到期 */
        if ($cardExpire > 0 && $cardExpire <= $now) {
            self::sealOff($pin, $writeBack);
            return ['authorized' => false, 'reason' => self::CARD_EXPIRED] + self::sealed($base);
        }

        /* 5. 在线校验窗口已过（断网太久 / 没续期） */
        if ($until <= $now) {
            return ['authorized' => false, 'reason' => self::WINDOW_EXPIRED] + $base;
        }

        return ['authorized' => true, 'reason' => self::OK] + $base;
    }

    /** 极简版：只要一个布尔值 + 原因 */
    public static function check(string $pin): array
    {
        $r = self::evaluate($pin);
        return [
            'ok'          => true,
            'authorized'  => $r['authorized'],
            'reason'      => $r['reason'],
            'pin'         => $r['pin'],
            'card'        => $r['card'],
            'card_status' => $r['card_status'],
            'card_expire_at'    => $r['card_expire_at'],
            'card_seconds_left' => $r['card_seconds_left'],
            'authorized_until'  => $r['authorized_until'],
            'expires_in'        => $r['expires_in'],
            'window'      => (int) Config::get('auth_window_sec', 600),
            'grace'       => (int) Config::get('grace_sec', 300),
            'server_time' => time(),
        ];
    }

    /** 封停后返回的字段：窗口一律按 0 报，避免客户端读到残留的有效期 */
    private static function sealed(array $base): array
    {
        $base['authorized_until'] = 0;
        $base['expires_in']       = 0;
        return $base;
    }

    /** 把某个配对码的在线窗口立刻清零 */
    public static function sealOff(string $pin, bool $write = true): void
    {
        if (!$write) {
            return;
        }
        try {
            Database::pdo()
                ->prepare('UPDATE pins SET authorized_until = 0 WHERE pin = ? AND authorized_until > 0')
                ->execute([$pin]);
        } catch (Throwable $e) {
            Log::file('app', 'authgate seal error: ' . $e->getMessage());
        }
    }

    /** 卡密状态变更（作废 / 删除 / 解绑）后，把所有绑定的配对码会话一并作废 */
    public static function sealByCard(int $cardId): int
    {
        if ($cardId <= 0) {
            return 0;
        }
        try {
            $st = Database::pdo()->prepare('UPDATE pins SET authorized_until = 0 WHERE card_id = ?');
            $st->execute([$cardId]);
            return $st->rowCount();
        } catch (Throwable $e) {
            Log::file('app', 'authgate sealByCard error: ' . $e->getMessage());
            return 0;
        }
    }

    /** 人类可读的原因（写日志 / 调试用） */
    public static function label(string $reason): string
    {
        switch ($reason) {
            case self::OK:             return '授权有效';
            case self::NO_CARD:        return '未绑定卡密';
            case self::CARD_NOT_FOUND: return '卡密不存在';
            case self::CARD_REVOKED:   return '卡密已作废';
            case self::CARD_EXPIRED:   return '卡密已过期';
            case self::WINDOW_EXPIRED: return '校验窗口已过期';
            default:                   return $reason;
        }
    }
}
