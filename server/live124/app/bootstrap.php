<?php
declare(strict_types=1);

/**
 * God 卡密验证系统 - 基础设施引导
 * PHP 8.0 / PDO SQLite / 无框架分层
 */

define('APP_ROOT', dirname(__DIR__));
define('APP_STORAGE', APP_ROOT . '/storage');

final class Config
{
    private static array $data = [];

    public static function load(): void
    {
        $file = APP_STORAGE . '/config.php';
        $defaults = [
            'db_path'        => APP_STORAGE . '/sqlite/app.db',
            'pin_len'        => 8,
            'grant_seconds'  => 300,          // 授权时长 5 分钟
            'poll_window'    => 3,            // 客户端轮询间隔(秒)，仅用于限流计算
            'rate_ip'        => 120,          // 每 IP 每分钟
            'rate_pin'       => 40,           // 每配对码每分钟
            'admin_session'  => 'god_admin_sid',
            /* 1.2.0 通道开关：
               allow_v3  = 0  → 只认 v4（存量老客户端会全部强制升级）
               allow_v2p = 0  → 连「明文 + HMAC 签名」的降级通道也关掉 */
            'allow_v3'       => 1,
            'allow_v2p'      => 1,
            'timezone'       => 'Asia/Shanghai',
        ];
        self::$data = is_file($file) ? array_merge($defaults, require $file) : $defaults;
        date_default_timezone_set(self::$data['timezone']);
    }

    public static function get(string $k, $def = null)
    {
        return self::$data[$k] ?? $def;
    }
}

final class Database
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }
        $path = Config::get('db_path');
        $dir = dirname($path);
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        $pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
        /* 顺序很关键：busy_timeout 必须先设。
           以前是先切 journal_mode=WAL，这一步需要拿写锁，一旦别的请求正在写，
           就直接抛 database is locked（日志里那些 500 就是这么来的）。
           WAL 是写进库文件的持久设置，本来也只需要设一次。 */
        $pdo->exec('PRAGMA busy_timeout=10000');
        $pdo->exec('PRAGMA synchronous=NORMAL');
        $pdo->exec('PRAGMA foreign_keys=ON');
        try {
            $mode = strtolower((string) $pdo->query('PRAGMA journal_mode')->fetchColumn());
            if ($mode !== 'wal') {
                $pdo->exec('PRAGMA journal_mode=WAL');
            }
        } catch (Throwable $e) {
            Log::file('app', 'wal switch skipped: ' . $e->getMessage());
        }
        self::migrate($pdo);
        return self::$pdo = $pdo;
    }

    /**
     * 结构迁移 —— 只在 schema.sql 变更时执行一次
     *
     * 原来是每次打开连接都跑一遍整个 schema.sql。
     * 建表语句虽然都是 IF NOT EXISTS，但 SQLite 执行时仍要拿写锁，
     * 并发一高就是 database is locked，接口直接 500。
     */
    private static function migrate(PDO $pdo): void
    {
        /* 增量加列：老库升级不用手工改表，服务端更新完直接生效。
           PRAGMA table_info 是纯内存读，每次连接跑一遍也没有开销。 */
        self::ensureColumns($pdo);

        $file = APP_ROOT . '/sql/schema.sql';
        $sql  = @file_get_contents($file);
        if ($sql === false) {
            throw new RuntimeException('schema.sql missing');
        }

        $marker = APP_STORAGE . '/cache/.schema-ok';
        $stamp  = (int) @filemtime($file);
        if ($stamp > 0 && is_file($marker) && (int) @file_get_contents($marker) === $stamp) {
            return;
        }

        $pdo->exec($sql);

        $dir = dirname($marker);
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        @file_put_contents($marker, (string) $stamp);
    }

    /**
     * 结构增量：缺哪一列补哪一列（SQLite 不支持 ADD COLUMN IF NOT EXISTS）
     *
     * 1.2.0 新增：
     *   cards.tier / ban_reason / banned_at     卡密分级 + 封禁原因
     *   pins.last_beat / app_ver / kick_at …    在线心跳 + 强制下线
     *   rule_sets.tiers                         规则集下发到哪些版本
     *   rule_packs.tier                         按版本分别生成的下发快照
     */
    private static function ensureColumns(PDO $pdo): void
    {
        $wants = [
            'cards' => [
                'tier'       => "TEXT NOT NULL DEFAULT 'pro'",
                'ban_reason' => "TEXT NOT NULL DEFAULT ''",
                'banned_at'  => 'INTEGER NOT NULL DEFAULT 0',
            ],
            'pins' => [
                'last_beat'   => 'INTEGER NOT NULL DEFAULT 0',
                'app_ver'     => "TEXT NOT NULL DEFAULT ''",
                'kick_at'     => 'INTEGER NOT NULL DEFAULT 0',
                'kick_reason' => "TEXT NOT NULL DEFAULT ''",
            ],
            'rule_sets' => [
                'tiers' => "TEXT NOT NULL DEFAULT ''",
            ],
            'rule_packs' => [
                'tier' => "TEXT NOT NULL DEFAULT 'all'",
            ],
        ];

        foreach ($wants as $table => $cols) {
            try {
                $info = $pdo->query('PRAGMA table_info(' . $table . ')')->fetchAll();
                if (!$info) {
                    continue;   /* 表还没建，等 schema.sql */
                }
                $have = [];
                foreach ($info as $row) {
                    $have[(string) $row['name']] = true;
                }
                foreach ($cols as $name => $decl) {
                    if (isset($have[$name])) {
                        continue;
                    }
                    $pdo->exec('ALTER TABLE ' . $table . ' ADD COLUMN ' . $name . ' ' . $decl);
                    Log::file('app', 'schema add column ' . $table . '.' . $name);
                }
            } catch (Throwable $e) {
                Log::file('app', 'schema ensure ' . $table . ' skipped: ' . $e->getMessage());
            }
        }
    }
}

final class Log
{
    public static function file(string $name, string $msg): void
    {
        $dir = APP_STORAGE . '/logs';
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        @file_put_contents(
            $dir . '/' . $name . '-' . date('Ymd') . '.log',
            sprintf("[%s] %s\n", date('Y-m-d H:i:s'), $msg),
            FILE_APPEND
        );
    }
}

final class Http
{
    public static function json($data, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        header('Cache-Control: no-store');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    public static function body(): array
    {
        $raw = file_get_contents('php://input') ?: '';
        if ($raw === '') {
            return $_POST ?: [];
        }
        $j = json_decode($raw, true);
        return is_array($j) ? $j : ($_POST ?: []);
    }

    /**
     * 客户端 IP
     *
     * 1.2.4 安全修复：以前无条件读 CF-Connecting-IP / X-Forwarded-For，
     * 而本站是 nginx 直连、前面没有 CDN —— 任何人只要自己带一个
     * `X-Forwarded-For: 1.2.3.4` 就能把 IP 改成任意值：
     *   · 限流按 IP 计数 → 换头即绕过（登录爆破、卡密枚举、心跳刷量）
     *   · 审计日志 / 封禁 / 强制下线全部记到伪造的地址上
     *   · 后台「在线设备」的 IP 也变成假的
     *
     * 现在默认只认 TCP 对端地址（REMOTE_ADDR）。只有在 config.php 里显式打开
     * `trust_proxy` 并且请求确实来自白名单里的反代时，才采用转发头。
     */
    public static function ip(): string
    {
        $remote = substr(trim((string) ($_SERVER['REMOTE_ADDR'] ?? '')), 0, 64);
        if ($remote === '') {
            $remote = '0.0.0.0';
        }

        if ((int) Config::get('trust_proxy', 0) !== 1) {
            return $remote;
        }

        $white = (array) Config::get('trusted_proxies', ['127.0.0.1', '::1']);
        if (!in_array($remote, $white, true)) {
            return $remote;
        }

        foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR'] as $k) {
            if (!empty($_SERVER[$k])) {
                $v = explode(',', (string) $_SERVER[$k])[0];
                $ip = filter_var(trim($v), FILTER_VALIDATE_IP);
                if ($ip !== false) {
                    return substr($ip, 0, 64);
                }
            }
        }
        return $remote;
    }

    public static function ua(): string
    {
        return substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255);
    }

    public static function abort(int $code, string $msg): void
    {
        self::json(['ok' => false, 'error' => $msg], $code);
    }
}

/**
 * 令牌桶限流：文件锁计数，窗口 60s
 *
 * 原来每条请求都往 SQLite 写一行，并发一高就 database is locked。
 * 改成本地文件 + flock：不碰数据库的写锁，几十个并发也不会互相顶掉。
 */
final class RateLimit
{
    public static function hit(string $key, int $limit): bool
    {
        $now = time();
        $win = 60;
        $dir = APP_STORAGE . '/cache/rate';
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        $file = $dir . '/' . sha1($key) . '.json';

        $fh = @fopen($file, 'c+');
        if (!$fh) {
            return true;   /* 拿不到文件就别拦用户 */
        }
        if (!flock($fh, LOCK_EX)) {
            fclose($fh);
            return true;
        }

        $raw   = stream_get_contents($fh);
        $hits  = $raw !== '' ? (json_decode($raw, true) ?: []) : [];
        if (!is_array($hits)) {
            $hits = [];
        }
        $keep = [];
        foreach ($hits as $t) {
            if (is_int($t) && $t >= $now - $win) {
                $keep[] = $t;
            }
        }

        if (count($keep) >= $limit) {
            flock($fh, LOCK_UN);
            fclose($fh);
            return false;
        }

        $keep[] = $now;
        ftruncate($fh, 0);
        rewind($fh);
        fwrite($fh, json_encode($keep));
        fflush($fh);
        flock($fh, LOCK_UN);
        fclose($fh);

        /* 小概率清理陈旧计数文件 */
        if (random_int(1, 50) === 1) {
            foreach ((array) @glob($dir . '/*.json') as $f) {
                if (@filemtime($f) < $now - 300) {
                    @unlink($f);
                }
            }
        }
        return true;
    }
}

Config::load();
