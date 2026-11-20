<?php
declare(strict_types=1);

/** 后台：登录 / 会话 / CSRF / 审计 */
final class AdminService
{
    public static function start(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        session_name((string) Config::get('admin_session', 'god_admin_sid'));
        session_set_cookie_params([
            'lifetime' => 0,
            'path'     => '/',
            'secure'   => (($_SERVER['HTTPS'] ?? '') !== '' && $_SERVER['HTTPS'] !== 'off'),
            'httponly' => true,
            'samesite' => 'Strict',
        ]);
        session_start();
    }

    public static function user(): ?string
    {
        self::start();
        return $_SESSION['admin'] ?? null;
    }

    public static function require(): string
    {
        $u = self::user();
        if (!$u) {
            Http::abort(401, 'unauthenticated');
        }
        return $u;
    }

    public static function csrf(): string
    {
        self::start();
        if (empty($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(24));
        }
        return $_SESSION['csrf'];
    }

    public static function checkCsrf(?string $token): void
    {
        self::start();
        if ($token === null || $token === '') {
            /* 老页面可能把 token 放在别的头或 body 里，统一兜一层 */
            foreach (['HTTP_X_CSRF', 'HTTP_X_CSRF_TOKEN', 'HTTP_X_XSRF_TOKEN', 'HTTP_X_XSRF'] as $k) {
                $v = $_SERVER[$k] ?? '';
                if (is_string($v) && $v !== '') { $token = trim($v); break; }
            }
        }
        if (($token === null || $token === '') && class_exists('Req', false)) {
            foreach (['_csrf', 'csrf', 'csrf_token'] as $k) {
                $v = Req::p($k, '');
                if (is_string($v) && $v !== '') { $token = trim($v); break; }
            }
        }
        $expect = (string) ($_SESSION['csrf'] ?? '');
        if ($token === null || $token === '' || $expect === '' || !hash_equals($expect, $token)) {
            Http::abort(419, 'csrf');
        }
    }

    public static function login(string $user, string $pass, string $ip): array
    {
        $pdo = Database::pdo();
        $st = $pdo->prepare('SELECT * FROM admins WHERE username = ? AND is_active = 1');
        $st->execute([$user]);
        $row = $st->fetch();
        if (!$row || !password_verify($pass, $row['pass_hash'])) {
            self::auditSafe($user, 'login.fail', $user, $ip, 'bad_credentials');
            return ['ok' => false, 'error' => 'bad_credentials'];
        }
        self::start();
        session_regenerate_id(true);
        $_SESSION['admin'] = $row['username'];
        $_SESSION['csrf']  = bin2hex(random_bytes(24));
        try {
            $pdo->prepare('UPDATE admins SET last_login = ? WHERE id = ?')->execute([time(), $row['id']]);
        } catch (Throwable $e) {
            /* 只是统计用，写不进去也不能让登录失败 */
            Log::file('app', 'last_login skip: ' . $e->getMessage());
        }
        self::auditSafe($row['username'], 'login.ok', $row['username'], $ip, '');
        /* 主人已经拿到密码了，initial 文件没有存在的必要 */
        self::dropInitialPassword();
        return ['ok' => true, 'user' => $row['username'], 'csrf' => $_SESSION['csrf']];
    }

    /** 审计写入：失败只记日志，绝不把登录/保存带崩（SQLite 高并发时偶发 busy） */
    private static function auditSafe(string $admin, string $action, string $target, string $ip, string $detail = ''): void
    {
        try {
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, $action, $target, $ip, substr($detail, 0, 255)]);
        } catch (Throwable $e) {
            Log::file('app', 'audit skip: ' . $e->getMessage());
        }
    }

    public static function logout(string $ip): void
    {
        self::start();
        $u = $_SESSION['admin'] ?? '';
        $_SESSION = [];
        session_destroy();
        if ($u) {
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $u, 'logout', $u, $ip, '']);
        }
    }

    public static function ensureSeedAdmin(): void
    {
        $pdo = Database::pdo();
        $n = (int) $pdo->query('SELECT COUNT(*) FROM admins')->fetchColumn();
        if ($n > 0) {
            return;
        }
        $pass = bin2hex(random_bytes(6));
        $pdo->prepare('INSERT INTO admins(username, pass_hash, created_at) VALUES(?,?,?)')
            ->execute(['admin', password_hash($pass, PASSWORD_DEFAULT), time()]);
        /* 1.2.4 安全修复：初始密码以前明文躺在 storage/admin_initial.txt 里永不清理，
           一旦备份 / 目录误配 / 运维手滑，等于后台钥匙直接送人。
           现在：只在首次创建时写一份、权限 600，并且登录成功后立刻删掉。 */
        $initFile = APP_STORAGE . '/admin_initial.txt';
        @file_put_contents($initFile,
            "username=admin\npassword={$pass}\ncreated=" . date('c') . "\n", LOCK_EX);
        @chmod($initFile, 0600);
    }

    /** 首次密码文件用完即删（登录成功一次就说明主人已经拿到密码了） */
    public static function dropInitialPassword(): void
    {
        $f = APP_STORAGE . '/admin_initial.txt';
        if (is_file($f)) {
            @unlink($f);
        }
    }

    public static function changePassword(string $user, string $newPass): void
    {
        Database::pdo()->prepare('UPDATE admins SET pass_hash = ? WHERE username = ?')
            ->execute([password_hash($newPass, PASSWORD_DEFAULT), $user]);
    }

    public static function auditLog(int $limit = 200): array
    {
        $st = Database::pdo()->prepare('SELECT ts, admin, action, target, ip, detail FROM audit ORDER BY id DESC LIMIT ?');
        $st->execute([$limit]);
        return $st->fetchAll();
    }

    public static function recentEvents(int $limit = 200): array
    {
        $st = Database::pdo()->prepare('SELECT ts, kind, pin, code, ip, detail FROM events ORDER BY id DESC LIMIT ?');
        $st->execute([$limit]);
        return $st->fetchAll();
    }
}
