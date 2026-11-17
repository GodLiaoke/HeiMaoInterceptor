<?php
declare(strict_types=1);

require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/Services/PinService.php';
require __DIR__ . '/../app/Services/SessionService.php';
require __DIR__ . '/../app/Services/CardService.php';
require __DIR__ . '/../app/Services/RulesService.php';
require __DIR__ . '/../app/Services/VersionService.php';
require __DIR__ . '/../app/Services/AdminService.php';
require __DIR__ . '/../app/Services/NoticeService.php';
require __DIR__ . '/../app/Services/CryptoService.php';
require __DIR__ . '/../app/Services/SettingsService.php';
require __DIR__ . '/../app/Services/AuthGate.php';
require __DIR__ . '/../app/Services/SecureV3.php';

$path   = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$path   = str_replace('/api/', '', $path);
$path   = trim($path, '/');
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$ip     = Http::ip();
$ua     = Http::ua();

header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
/* 抓包只能看到密文，禁止任何中间层缓存 */
header('Cache-Control: no-store');

/* v3 加密请求一律 POST 传输（GET 会进日志/代理缓存），内部按原语义路由 */
Req::init($path);
$getOnlyRoutes = ['pin/status', 'session/state', 'app/version', 'notice', 'announcement'];
$routeMethod = (Req::isSecure() && in_array($path, $getOnlyRoutes, true)) ? 'GET' : $method;

try {
    switch ($path . '|' . $routeMethod) {

        // ---------- 客户端：配对码状态轮询（每 3 秒一次） ----------
        case 'pin/status|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) (Req::p('pin', '')));
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('pin:' . $pin, (int) Config::get('rate_pin'))) {
                Res::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $st = PinService::status($pin);
            Res::json(['ok' => true] + $st);
        }

        // ---------- 客户端：强校验（App 启动 / 回前台 / 开 VPN 前必调） ----------
        // 每次都查库，不看任何缓存；卡密作废或过期会当场把会话封掉。
        case 'auth/check|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) (Req::p('pin', '')));
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('ac:' . $pin, 60)) {
                Res::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $r = AuthGate::check($pin);
            if (!$r['authorized']) {
                CardService::event('auth_check_fail', $pin, null, $ip, $ua, (string) $r['reason']);
            }
            Res::json($r);
        }

        // ---------- 客户端：心跳登记 ----------
        case 'pin/beat|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            PinService::touch($pin, $ip, $ua);
            Res::json(['ok' => true] + PinService::status($pin));
        }

        // ---------- 网页：配对码 + 卡密兑换 ----------
        case 'card/redeem|POST': {
            if (!RateLimit::hit('ip:' . $ip, 10) || !RateLimit::hit('rdm:' . $ip, 10)) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rdp:' . $pin, 6)) {
                Res::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $r = CardService::redeem($pin, $code, $ip, $ua);
            if (!$r['ok']) {
                Res::json(['ok' => false, 'error' => $r['error']], 200);
            }
            /* 同时返回窗口（expire_at，兼容旧客户端）与卡密真实到期（card_expire_at） */
            Res::json($r);
        }

        // ---------- 客户端：续期（只推窗口，不产生兑换记录） ----------
        case 'session/renew|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rn:' . $pin, 30)) {
                Res::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $r = SessionService::renew($pin, $code, $ip, $ua);
            if (!$r['ok']) {
                Res::json(['ok' => false, 'error' => $r['error']], 200);
            }
            Res::json($r);
        }

        // ---------- 客户端：只读状态（不改计数） ----------
        case 'session/state|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) (Req::p('pin', '')));
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            Res::json(SessionService::state($pin));
        }

        // ---------- 客户端：云端规则库（必须有效卡密） ----------
        case 'rules/manifest|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rm:' . $pin, 30)) {
                Res::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $s = SessionService::renew($pin, $code, $ip, $ua);
            if (!$s['ok']) {
                Res::json(['ok' => false, 'error' => $s['error']], 403);
            }
            Res::json(RulesService::manifest());
        }

        case 'rules/download|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = CardService::normalise((string) ($b['code'] ?? ''));
            if (!PinService::valid($pin)) {
                Res::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rd:' . $pin, 20)) {
                Res::abort(429, 'rate_limited');
            }
            $s = SessionService::renew($pin, $code, $ip, $ua);
            if (!$s['ok']) {
                Res::json(['ok' => false, 'error' => $s['error']], 403);
            }
            $pack = RulesService::current();
            if (!$pack) {
                Res::json(['ok' => false, 'error' => 'no_rules'], 404);
            }
            $want = (string) ($b['version'] ?? '');
            if ($want !== '' && $want !== (string) $pack['version']) {
                Res::json(['ok' => false, 'error' => 'version_mismatch',
                            'version' => $pack['version']], 409);
            }
            [$bucket] = RulesService::bucket();
            $key = RulesService::deriveKey($pin, $code, $bucket, (string) $pack['version']);
            $blob = RulesService::encrypt(RulesService::content((int) $pack['id']), $key);

            /* 加密请求：整包再套一层 v3 信封（密文里再 base64）；
               明文请求：保持原来的 octet-stream，老客户端不受影响 */
            Res::binary($blob, [
                'rules_version' => (string) $pack['version'],
                'rules_sha256'  => (string) $pack['sha256'],
                'rules_bucket'  => $bucket,
            ]);
        }

        // ---------- 客户端：版本检测 ----------
        case 'app/version|GET': {
            if (!RateLimit::hit('ver:' . $ip, 120)) {
                Res::abort(429, 'rate_limited');
            }
            Res::json(VersionService::check(
                (string) (Req::p('platform', 'ios')),
                (string) (Req::p('current', ''))
            ));
        }

        // ---------- 客户端：公告/授权状态（复用脚本自带 HTTP 拉取通道） ----------
        case 'notice|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) (Req::p('pin', '')));
            $ann = NoticeService::currentText();

            /* 不带 pin：纯公告模式（无卡密版客户端走这条） */
            if (!PinService::valid($pin)) {
                $text = $ann !== '' ? $ann : '欢迎使用 God 全系统';
                /* msg 与 notice 都放公告正文：客户端取任一字段都能显示 */
                Res::json(['code' => 200, 'msg' => $text, 'notice' => $text,
                            'announcement' => $ann]);
            }
            PinService::touch($pin, $ip, $ua);
            $st = PinService::status($pin);
            $ann = NoticeService::currentText();

            if (!$st['authorized']) {
                /* 未授权：notice 返回布尔 false —— 客户端据此不构建菜单 */
                Res::json(['code' => 200, 'msg' => 'ok', 'notice' => false,
                            'announcement' => $ann, 'authorized' => false]);
            }
            $text = '到期时间：' . date('Y-m-d H:i:s', $st['expire_at']);
            if ($ann !== '') {
                $text = $ann . ' ｜ ' . $text;
            }
            Res::json(['code' => 200, 'msg' => 'ok', 'notice' => $text,
                        'announcement' => $ann, 'authorized' => true]);
        }

        // ---------- 公开：当前公告（用户页顶部展示） ----------
        case 'announcement|GET': {
            $c = NoticeService::current();
            Res::json(['ok' => true, 'title' => $c['title'], 'content' => $c['content'],
                        'updated_at' => $c['updated_at']]);
        }

        // ---------- 后台：公告管理 ----------
        case 'admin/notice|GET': {
            AdminService::require();
            Res::json(['ok' => true, 'current' => NoticeService::current(),
                        'history' => NoticeService::history(20)]);
        }

        case 'admin/notice/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $r = NoticeService::save((string) ($b['title'] ?? ''), (string) ($b['content'] ?? ''), $admin, $ip);
            Res::json(['ok' => true] + $r);
        }

        case 'admin/notice/clear|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            NoticeService::clear($admin, $ip);
            Res::json(['ok' => true]);
        }

        // ---------- 后台登录 ----------
        case 'admin/login|POST': {
            if (!RateLimit::hit('login:' . $ip, 10)) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $r = AdminService::login((string) ($b['username'] ?? ''), (string) ($b['password'] ?? ''), $ip);
            if (!$r['ok']) {
                Res::json($r, 401);
            }
            Res::json($r);
        }

        case 'admin/logout|POST': {
            AdminService::require();
            AdminService::logout($ip);
            Res::json(['ok' => true]);
        }

        // ---------- 后台数据 ----------
        case 'admin/stats|GET': {
            AdminService::require();
            Res::json(['ok' => true] + CardService::stats());
        }

        case 'admin/cards|GET': {
            AdminService::require();
            $page = max(1, (int) Req::p('page', 1));
            $per  = min(100, max(10, (int) Req::p('per', 20)));
            $q    = trim((string) (Req::p('q', '')));
            $st   = (int) Req::p('status', -1);
            $bt   = trim((string) (Req::p('batch', '')));
            Res::json(['ok' => true] + CardService::listPage($page, $per, $q, $st, $bt));
        }

        case 'admin/cards/generate|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $plan = (string) ($b['plan'] ?? 'all');
            $planTag = in_array($plan, ['basic', 'pro'], true) ? ('plan:' . $plan . ' ') : '';
            $charset = (string) ($b['charset'] ?? 'std');
            if (!in_array($charset, ['std', 'digit', 'alpha', 'full'], true)) {
                $charset = 'std';
            }
            $r = CardService::createBatch(
                (int) ($b['count'] ?? 10),
                (int) ($b['duration'] ?? Config::get('grant_seconds', 300)),
                substr((string) ($b['batch'] ?? 'B' . date('Ymd')), 0, 32),
                $planTag . substr((string) ($b['note'] ?? ''), 0, 110),
                $admin, $ip, $charset
            );
            Res::json(['ok' => true] + $r);
        }

        case 'admin/cards/status|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $ok = CardService::setStatus((int) ($b['id'] ?? 0), (int) ($b['status'] ?? 0), $admin, $ip);
            Res::json(['ok' => $ok]);
        }

        case 'admin/cards/extend|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $days = (int) ($b['days'] ?? 0);
            if ($days === 0 || abs($days) > 3650) {
                Res::json(['ok' => false, 'error' => 'bad_days'], 400);
            }
            Res::json(CardService::extend((int) ($b['id'] ?? 0), $days, $admin, $ip));
        }

        case 'admin/cards/delete|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            Res::json(['ok' => CardService::remove((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        case 'admin/cards/unbind|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            Res::json(['ok' => CardService::unbind((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        // ---------- 后台：版本管理 ----------
        case 'admin/versions|GET': {
            AdminService::require();
            Res::json(['ok' => true, 'rows' => VersionService::all()]);
        }

        case 'admin/versions/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $r = VersionService::save(Req::all(), $admin, $ip);
            Res::json($r, $r['ok'] ? 200 : 400);
        }

        case 'admin/versions/delete|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            Res::json(['ok' => VersionService::remove((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        // ---------- 后台：云端规则库 ----------
        case 'admin/rules|GET': {
            AdminService::require();
            $pack = RulesService::current();
            if (!$pack) {
                Res::json(['ok' => true, 'current' => null, 'content' => '']);
            }
            Res::json(['ok' => true, 'current' => $pack, 'content' => RulesService::content((int) $pack['id'])]);
        }

        case 'admin/rules/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $r = RulesService::save(
                (string) ($b['version'] ?? ''),
                (string) ($b['note'] ?? ''),
                (string) ($b['content'] ?? ''),
                $admin, $ip
            );
            Res::json($r, $r['ok'] ? 200 : 400);
        }

        case 'admin/pins|GET': {
            AdminService::require();
            Res::json(['ok' => true, 'rows' => PinService::offlineList(200)]);
        }


        case 'admin/logs|GET': {
            AdminService::require();
            Res::json(['ok' => true,
                        'audit'  => AdminService::auditLog(100),
                        'events' => AdminService::recentEvents(150)]);
        }

        case 'admin/csrf|GET': {
            AdminService::require();
            Res::json(['ok' => true, 'csrf' => AdminService::csrf()]);
        }

        // ---------- 后台：批量 / 导出 / 设置 / 改密 / 危险操作 ----------
        case 'admin/batches|GET': {
            AdminService::require();
            $rows = Database::pdo()->query('SELECT batch, COUNT(*) c FROM cards GROUP BY batch ORDER BY MAX(id) DESC LIMIT 100')->fetchAll();
            Res::json(['ok' => true, 'rows' => $rows]);
        }

        case 'admin/cards/bulk|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $ids = $b['ids'] ?? [];
            if (!is_array($ids) || count($ids) === 0) {
                Res::json(['ok' => false, 'error' => 'no_selection'], 400);
            }
            $action = (string) ($b['action'] ?? '');
            $days   = (int) ($b['days'] ?? 0);
            $done = 0;
            foreach ($ids as $id) {
                $id = (int) $id;
                if ($id <= 0) continue;
                if ($action === 'ban')      { CardService::setStatus($id, 2, $admin, $ip); $done++; }
                elseif ($action === 'unban'){ CardService::setStatus($id, 0, $admin, $ip); $done++; }
                elseif ($action === 'delete'){ CardService::remove($id, $admin, $ip); $done++; }
                elseif ($action === 'extend' && $days !== 0) { CardService::extend($id, $days, $admin, $ip); $done++; }
            }
            Res::json(['ok' => true, 'done' => $done]);
        }

        case 'admin/cards/export|GET': {
            AdminService::require();
            $q  = trim((string) (Req::p('q', '')));
            $st = (int) Req::p('status', -1);
            $bt = trim((string) (Req::p('batch', '')));
            $page = CardService::listPage(1, 2000, $q, $st, $bt);
            header('Content-Type: text/csv; charset=utf-8');
            header('Content-Disposition: attachment; filename="cards-' . date('Ymd-His') . '.csv"');
            echo "\xEF\xBB\xBF";
            $out = fopen('php://output', 'w');
            fputcsv($out, ['卡密', '批次', '时长(天)', '状态', '绑定配对码', '兑换时间', '到期时间', '备注']);
            $map = [0 => '未使用', 1 => '已兑换', 2 => '已作废'];
            foreach ($page['rows'] as $r) {
                fputcsv($out, [
                    $r['code'], $r['batch'], round(((int) $r['duration_sec']) / 86400, 2),
                    $map[(int) $r['status']] ?? '?', $r['bound_pin'] ?: '',
                    $r['redeemed_at'] ? date('Y-m-d H:i:s', (int) $r['redeemed_at']) : '',
                    $r['expire_at'] ? date('Y-m-d H:i:s', (int) $r['expire_at']) : '',
                    (string) ($r['note'] ?? ''),
                ]);
            }
            fclose($out);
            exit;
        }

        case 'admin/settings|GET': {
            AdminService::require();
            Res::json(['ok' => true, 'settings' => Settings::all()]);
        }

        case 'admin/settings/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            Settings::save([
                'default_count'  => max(1, min(1000, (int) ($b['default_count'] ?? 10))),
                'default_days'   => max(1, min(3650, (int) ($b['default_days'] ?? 30))),
                'default_plan'   => in_array($b['default_plan'] ?? '', ['all', 'basic', 'pro'], true) ? $b['default_plan'] : 'all',
                'default_charset'=> in_array($b['default_charset'] ?? '', ['std', 'digit', 'alpha', 'full'], true) ? $b['default_charset'] : 'std',
                'batch_prefix'   => substr(preg_replace('/[^A-Za-z0-9]/', '', (string) ($b['batch_prefix'] ?? 'B')), 0, 8) ?: 'B',
            ], $admin);
            Res::json(['ok' => true, 'settings' => Settings::all()]);
        }

        case 'admin/password|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $cur = (string) ($b['current'] ?? '');
            $new = (string) ($b['new'] ?? '');
            if (strlen($new) < 8) {
                Res::json(['ok' => false, 'error' => 'too_short'], 400);
            }
            $st = Database::pdo()->prepare('SELECT pass_hash FROM admins WHERE username = ?');
            $st->execute([$admin]);
            $hash = (string) $st->fetchColumn();
            if (!password_verify($cur, $hash)) {
                Res::json(['ok' => false, 'error' => 'bad_current'], 400);
            }
            AdminService::changePassword($admin, $new);
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'password.change', $admin, $ip, '']);
            Res::json(['ok' => true]);
        }

        case 'admin/pins/revoke|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Res::json(['ok' => false, 'error' => 'bad_pin'], 400);
            }
            PinService::revoke($pin);
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'pin.revoke', $pin, $ip, '']);
            Res::json(['ok' => true]);
        }

        case 'admin/danger|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Req::all();
            $what = (string) ($b['action'] ?? '');
            $pdo = Database::pdo();
            $n = 0;
            if ($what === 'clear_unused_cards') {
                $n = (int) $pdo->query('SELECT COUNT(*) FROM cards WHERE status = 0')->fetchColumn();
                $pdo->exec('DELETE FROM cards WHERE status = 0');
            } elseif ($what === 'clear_logs') {
                $n = (int) $pdo->query('SELECT COUNT(*) FROM audit')->fetchColumn();
                $pdo->exec('DELETE FROM audit');
                $pdo->exec('DELETE FROM events');
            } else {
                Res::json(['ok' => false, 'error' => 'unknown'], 400);
            }
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'danger.' . $what, '', $ip, 'rows=' . $n]);
            Res::json(['ok' => true, 'affected' => $n]);
        }

        // ---------- v2：加密通道（握手 / 卡密 / 服务端模块） ----------
        case 'v2/handshake|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $c = Crypto::checkRequest('handshake', $b);
            if (!$c) {
                Res::abort(400, 'bad_sig');
            }
            PinService::touch($c['pin'], $ip, $ua);
            Res::json(Crypto::statusBox($c['pin'], $c['dev'], $c['n']));
        }

        case 'v2/card|POST': {
            if (!RateLimit::hit('ip:' . $ip, 30) || !RateLimit::hit('v2c:' . $ip, 30)) {
                Res::abort(429, 'rate_limited');
            }
            $b = Req::all();
            $c = Crypto::checkRequest('card', $b);
            if (!$c) {
                Res::abort(400, 'bad_sig');
            }
            PinService::touch($c['pin'], $ip, $ua);
            $code = (string) ($b['code'] ?? '');
            $r = CardService::redeem($c['pin'], $code, $ip, $ua);
            if (!$r['ok']) {
                Res::json(Crypto::box(['ok' => false, 'error' => $r['error']], $c['n']));
            }
            Res::json(Crypto::statusBox($c['pin'], $c['dev'], $c['n']));
        }

        // 服务端下发 Lua 模块（客户端验签后 load）：把功能函数真正放到服务器上
        case 'v2/module|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) (Req::p('pin', '')));
            $st  = PinService::valid($pin) ? PinService::status($pin) : ['authorized' => false];
            if (empty($st['authorized'])) {
                Res::json(['ok' => false, 'error' => 'not_authorized']);
            }
            $file = APP_STORAGE . '/remote/module.lua';
            $src  = is_file($file) ? (string) file_get_contents($file) : '';
            if ($src === '') {
                Res::json(['ok' => false, 'error' => 'no_module']);
            }
            Res::json([
                'ok'  => true,
                'src' => base64_encode($src),
                'sig' => Crypto::sign('l|' . $src),
            ]);
        }

        // ---------- GOD 注入器：卡密换 lua ----------
        case 'god/download|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Res::abort(429, 'rate_limited');
            }
            $code = CardService::normalise((string) (Req::p('card', '')));
            if (!preg_match('/^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$/', $code)) {
                Res::json(['ok' => false, 'error' => 'card_format'], 400);
            }
            $pdo = Database::pdo();
            $st = $pdo->prepare('SELECT id, status, expire_at FROM cards WHERE code = ?');
            $st->execute([$code]);
            $card = $st->fetch();
            if (!$card) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'not_found');
                Res::json(['ok' => false, 'error' => 'card_not_found'], 404);
            }
            if ((int) $card['status'] === 2) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'revoked');
                Res::json(['ok' => false, 'error' => 'card_revoked'], 403);
            }
            $now = time();
            if ((int) $card['status'] === 1 && (int) $card['expire_at'] <= $now) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'expired');
                Res::json(['ok' => false, 'error' => 'card_expired'], 403);
            }
            $file = APP_STORAGE . '/god/EntranceFlow.lua';
            if (!is_file($file)) {
                Res::json(['ok' => false, 'error' => 'no_file'], 500);
            }
            CardService::event('god_download', null, $code, $ip, $ua, 'ok');
            header('Content-Type: application/octet-stream');
            header('Content-Length: ' . filesize($file));
            header('Content-Disposition: attachment; filename="EntranceFlow.lua"');
            header('Cache-Control: no-store');
            readfile($file);
            exit;
        }

        default:
            Res::abort(404, 'not_found');
    }
} catch (Throwable $e) {
    Log::file('app', 'api fatal: ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine());
    Res::json(['ok' => false, 'error' => 'server_error'], 500);
}
