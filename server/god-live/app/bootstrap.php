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
        $pdo->exec('PRAGMA journal_mode=WAL');
        $pdo->exec('PRAGMA synchronous=NORMAL');
        $pdo->exec('PRAGMA busy_timeout=10000');
        $pdo->exec('PRAGMA foreign_keys=ON');
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

    public static function ip(): string
    {
        foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'REMOTE_ADDR'] as $k) {
            if (!empty($_SERVER[$k])) {
                $v = explode(',', (string) $_SERVER[$k])[0];
                return substr(trim($v), 0, 64);
            }
        }
        return '0.0.0.0';
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
