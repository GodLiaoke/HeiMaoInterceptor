<?php
declare(strict_types=1);

/** 后台可调项（生成默认值 / 卡密样式） */
final class Settings
{
    private const DEFAULTS = [
        'default_count'   => 10,
        'default_days'    => 30,
        'default_plan'    => 'all',
        'default_charset' => 'std',
        'batch_prefix'    => 'B',
        /* 1.2.3 运维开关 */
        'maintenance_on'     => 0,
        'maintenance_reason' => '',
        'fuse_mode'          => 'off',   /* off / all / below */
        'fuse_build'         => 0,
        'fuse_reason'        => '',
        /* 1.2.4：低于这个 build 的客户端拿不到规则包，也过不了心跳闸门 */
        'min_build'          => 0,
    ];

    public static function all(): array
    {
        $out = self::DEFAULTS;
        try {
            $rows = Database::pdo()->query('SELECT k, v FROM settings')->fetchAll();
            foreach ($rows as $r) {
                if (array_key_exists($r['k'], $out)) {
                    $out[$r['k']] = is_numeric($r['v']) ? (int) $r['v'] : $r['v'];
                }
            }
        } catch (Throwable $e) {
            /* 表还没建好就返回默认值 */
        }
        return $out;
    }

    /** 维护模式：开启后客户端进入维护页，下方显示原因 */
    public static function maintenance(): array
    {
        $s = self::all();
        return [
            'on'     => ((int) ($s['maintenance_on'] ?? 0)) === 1,
            'reason' => (string) ($s['maintenance_reason'] ?? ''),
        ];
    }

    /**
     * 熔断：防破解兜底
     *   off   = 关闭
     *   all   = 所有版本熔断
     *   below = build 低于 fuse_build 的版本熔断
     */
    public static function fuse(): array
    {
        $s = self::all();
        $mode = (string) ($s['fuse_mode'] ?? 'off');
        if (!in_array($mode, ['off', 'all', 'below'], true)) {
            $mode = 'off';
        }
        return [
            'mode'   => $mode,
            'build'  => max(0, (int) ($s['fuse_build'] ?? 0)),
            'reason' => (string) ($s['fuse_reason'] ?? ''),
        ];
    }

    public static function save(array $map, string $admin): void
    {
        $pdo = Database::pdo();
        /* 这台机器的 SQLite 是 3.7，不支持 UPSERT，用 OR REPLACE 等价实现 */
        $st = $pdo->prepare('INSERT OR REPLACE INTO settings(k, v, updated_at) VALUES(?,?,?)');
        foreach ($map as $k => $v) {
            $st->execute([$k, (string) $v, time()]);
        }
        $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
            ->execute([time(), $admin, 'settings.save', 'settings', '', json_encode($map, JSON_UNESCAPED_UNICODE)]);
    }
}
